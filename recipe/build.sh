set -ex

if [[ "${target_platform}" == osx-* ]]; then
    source gen-bazel-toolchain
    echo "build --crosstool_top=//bazel_toolchain:toolchain" >> .bazelrc
fi

cat >> .bazelrc <<EOF
build --logging=6
build --verbose_failures
build --define=PREFIX=${PREFIX}
build --define=PROTOBUF_INCLUDE_PATH=${PREFIX}/include
build --local_cpu_resources=${CPU_COUNT}
EOF

bazel clean --expunge
bazel shutdown

bazel build //tensorboard/pip_package:build_pip_package

RUNFILES="bazel-bin/tensorboard/pip_package/build_pip_package.runfiles/org_tensorflow_tensorboard"

# Create a clean temporary directory for building the package
BUILD_DIR=$(mktemp -d)
cd "${BUILD_DIR}"

# Copy the built files from Bazel runfiles
cp -LR "${SRC_DIR}/${RUNFILES}/tensorboard" .

# Vendor bleach and webencodings as TensorBoard expects
mkdir -p tensorboard/_vendor
touch tensorboard/_vendor/__init__.py
cp -LR "${SRC_DIR}/bazel-bin/tensorboard/pip_package/build_pip_package.runfiles/org_mozilla_bleach/bleach" tensorboard/_vendor/
cp -LR "${SRC_DIR}/bazel-bin/tensorboard/pip_package/build_pip_package.runfiles/org_pythonhosted_webencodings/webencodings" tensorboard/_vendor/

if [[ "${target_platform}" == osx-* ]]; then
    sedi="sed -i ''"
else
    sedi="sed -i"
fi

find tensorboard -name '*.py' -exec ${sedi} -e '
  s/^import bleach$/from tensorboard._vendor import bleach/
  s/^from bleach/from tensorboard._vendor.bleach/
  s/^import webencodings$/from tensorboard._vendor import webencodings/
  s/^from webencodings/from tensorboard._vendor.webencodings/
' {} +

# Move the pip_package files to the root
mv -f tensorboard/pip_package/LICENSE .
mv -f tensorboard/pip_package/MANIFEST.in .
mv -f tensorboard/pip_package/README.rst .
mv -f tensorboard/pip_package/requirements.txt .
mv -f tensorboard/pip_package/setup.cfg .
mv -f tensorboard/pip_package/setup.py .
rm -rf tensorboard/pip_package

# Ensure MANIFEST.in includes the vendor directory
cat >> MANIFEST.in <<MANIFEST_EOF
recursive-include tensorboard/_vendor *.py
recursive-include tensorboard/_vendor *.html
recursive-include tensorboard/_vendor *.css
MANIFEST_EOF

rm -f tensorboard/tensorboard  # bazel py_binary sh wrapper
chmod -x LICENSE  # bazel symlinks confuse cp
find . -name __init__.py -exec chmod -x {} +  # which goes for all genfiles

# Get rid of cyclic import, and set the version
${sedi} '/^import tensorboard\.version$/d' setup.py
${sedi} "s/version=tensorboard\.version\.VERSION\.replace(\"-\", \"\"),/version=\"${PKG_VERSION}\",/" setup.py

# Install using conda's Python
$PYTHON setup.py install --single-version-externally-managed --record=record.txt