%PYTHON% -m pip install --no-deps --ignore-installed .\tensorboard-%PKG_VERSION%-py3-none-any.whl
if errorlevel 1 exit 1
REM Remove the strict protobuf requirement. Conda will manage it.
sed -i 's/^Requires-Dist: protobuf.*/Requires-Dist: protobuf/' %SP_DIR%\tensorboard-%PKG_VERSION%.dist-info\METADATA
if errorlevel 1 exit 1
