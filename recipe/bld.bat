@echo on

:: Configure Bazel
echo build --logging=6 >> .bazelrc
echo build --verbose_failures >> .bazelrc
echo build --define=PREFIX=%PREFIX% >> .bazelrc
echo build --define=PROTOBUF_INCLUDE_PATH=%PREFIX%/include >> .bazelrc
echo build --local_cpu_resources=%CPU_COUNT% >> .bazelrc

bazel clean --expunge
if errorlevel 1 exit 1

bazel shutdown
if errorlevel 1 exit 1

:: Build with Bazel
bazel build //tensorboard/pip_package:build_pip_package
if errorlevel 1 exit 1

set RUNFILES=bazel-bin/tensorboard/pip_package/build_pip_package.runfiles/org_tensorflow_tensorboard

:: Create a clean temporary directory for building the package
set BUILD_DIR=%TEMP%\tensorboard_build_%RANDOM%
mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

:: Copy the built files from Bazel runfiles
xcopy /E /I /Q "%SRC_DIR%\%RUNFILES%\tensorboard" tensorboard
if errorlevel 1 exit 1

:: Vendor bleach and webencodings as TensorBoard expects
mkdir tensorboard\_vendor
echo. > tensorboard\_vendor\__init__.py
xcopy /E /I /Q "%SRC_DIR%\bazel-bin\tensorboard\pip_package\build_pip_package.runfiles\org_mozilla_bleach\bleach" tensorboard\_vendor\bleach
if errorlevel 1 exit 1
xcopy /E /I /Q "%SRC_DIR%\bazel-bin\tensorboard\pip_package\build_pip_package.runfiles\org_pythonhosted_webencodings\webencodings" tensorboard\_vendor\webencodings
if errorlevel 1 exit 1

:: Patch imports to use vendored packages
for /r tensorboard %%f in (*.py) do (
    sed -i -e "s/^import bleach$/from tensorboard._vendor import bleach/" -e "s/^from bleach/from tensorboard._vendor.bleach/" -e "s/^import webencodings$/from tensorboard._vendor import webencodings/" -e "s/^from webencodings/from tensorboard._vendor.webencodings/" "%%f"
)

:: Move the pip_package files to the root
move /Y tensorboard\pip_package\LICENSE .
move /Y tensorboard\pip_package\MANIFEST.in .
move /Y tensorboard\pip_package\README.rst .
move /Y tensorboard\pip_package\requirements.txt .
move /Y tensorboard\pip_package\setup.cfg .
move /Y tensorboard\pip_package\setup.py .
rmdir /S /Q tensorboard\pip_package

:: Ensure MANIFEST.in includes the vendor directory
echo recursive-include tensorboard/_vendor *.py >> MANIFEST.in
echo recursive-include tensorboard/_vendor *.html >> MANIFEST.in
echo recursive-include tensorboard/_vendor *.css >> MANIFEST.in

:: Remove the Bazel wrapper script if it exists
if exist tensorboard\tensorboard del /F tensorboard\tensorboard

:: Get rid of cyclic import, and set the version
sed -i "/^import tensorboard\.version$/d" setup.py
sed -i "s/version=tensorboard\.version\.VERSION\.replace(\"-\", \"\"),/version=\"%PKG_VERSION%\",/" setup.py

:: Install using conda's Python
%PYTHON% setup.py install --single-version-externally-managed --record=record.txt
if errorlevel 1 exit 1
