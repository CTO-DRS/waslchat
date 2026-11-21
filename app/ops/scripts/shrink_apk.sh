#!/bin/bash
# Shrink & re-sign the debug APK: strip libflutter.so, drop Vulkan validation layer
set -e
T=/workspace/tools; IN=$T/wc/build/app/outputs/flutter-apk/app-debug.apk; OUT=${1:-$T/wasl_chat.apk}
export JAVA_HOME=$T/jdk PATH=$T/jdk/bin:$PATH
W=$T/apkwork; rm -rf $W; mkdir -p $W/x; cd $W/x
unzip -q $IN
rm -rf META-INF lib/arm64-v8a/libVkLayer_khronos_validation.so
python3 /workspace/tools/elfstrip.py lib/arm64-v8a/libflutter.so lib/arm64-v8a/libflutter.s && mv lib/arm64-v8a/libflutter.s lib/arm64-v8a/libflutter.so
ls -la lib/arm64-v8a/
# libs stored (uncompressed), rest deflated
zip -q -r -D -X ../u.zip . -x 'lib/*' 'resources.arsc'
zip -q -r -D -X -0 ../u.zip lib resources.arsc
$T/armtools/build-tools/zipalign -f -p 4 ../u.zip ../a.apk
KS=$T/wasl-debug.jks
[ -f $KS ] || keytool -genkeypair -keystore $KS -storepass android -keypass android -alias wasl -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Wasl Chat" >/dev/null 2>&1
java -jar $T/android-sdk/build-tools/35.0.0/lib/apksigner.jar sign --ks $KS --ks-pass pass:android --ks-key-alias wasl --out $OUT ../a.apk
java -jar $T/android-sdk/build-tools/35.0.0/lib/apksigner.jar verify $OUT && ls -la $OUT
