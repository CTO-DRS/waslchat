#!/bin/bash
set -e
export ANDROID_HOME=/workspace/tools/android-sdk; export GRADLE_USER_HOME=/workspace/tools/gradle; export PUB_CACHE=/workspace/tools/pub-cache
export PATH=/workspace/tools/flutter/bin:$PATH
echo "== jdk"
export JAVA_HOME=/workspace/tools/jdk; export PATH=$JAVA_HOME/bin:$PATH
java -version 2>&1 | head -1
(python3 /workspace/tools/localproxy.py >/tmp/proxy.log 2>&1 &) ; sleep 1
export JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=18888 -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=18888 -Dhttp.nonProxyHosts=localhost|127.0.0.1"
printf "systemProp.https.proxyHost=127.0.0.1\nsystemProp.https.proxyPort=18888\nsystemProp.http.proxyHost=127.0.0.1\nsystemProp.http.proxyPort=18888\norg.gradle.jvmargs=-Xmx2g\nkotlin.compiler.execution.strategy=in-process\norg.gradle.workers.max=2\n" > $GRADLE_USER_HOME/gradle.properties
echo "== sdk"
mkdir -p $ANDROID_HOME/cmdline-tools
if [ ! -d $ANDROID_HOME/cmdline-tools/latest ]; then
  curl -sL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/clt.zip
  cd /tmp && unzip -q clt.zip && mv cmdline-tools $ANDROID_HOME/cmdline-tools/latest && rm clt.zip
fi
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --proxy=http --proxy_host=127.0.0.1 --proxy_port=18888 --licenses >/dev/null 2>&1 || true
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --proxy=http --proxy_host=127.0.0.1 --proxy_port=18888 "platforms;android-35" "platforms;android-36" "build-tools;35.0.0" "platform-tools" "ndk;28.2.13676358" 2>&1 | grep -v "^\[" | tail -5 || true
ls $ANDROID_HOME/platforms
echo "== arm64 aapt2"
if [ ! -f /workspace/tools/armtools/aapt2 ]; then
  mkdir -p /workspace/tools/armtools && cd /workspace/tools/armtools
  curl -sL https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip -o t.zip && unzip -qo t.zip && rm t.zip
  find . -name aapt2 -type f -exec cp {} /workspace/tools/armtools/aapt2 \; ; chmod +x /workspace/tools/armtools/aapt2
fi
/workspace/tools/armtools/aapt2 version || true
# replace x86 build-tools binaries with arm64 ones
for b in aapt aapt2 aidl zipalign dexdump split-select; do
  f=$(find /workspace/tools/armtools -name $b -type f | head -1); [ -n "$f" ] && cp "$f" $ANDROID_HOME/build-tools/35.0.0/$b && chmod +x $ANDROID_HOME/build-tools/35.0.0/$b || true
done
flutter config --android-sdk $ANDROID_HOME >/dev/null
echo "== project"
rm -rf /workspace/tools/wc && cp -r /workspace/projects/9a838610-9601-4b0f-94c2-29d056b94775/wasl_chat /workspace/tools/wc && cd /workspace/tools/wc
flutter create --platforms android --org app.waslchat --project-name wasl_chat . >/dev/null
echo "android.aapt2FromMavenOverride=/workspace/tools/armtools/aapt2" >> android/gradle.properties
M=android/app/src/main/AndroidManifest.xml
sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application#' $M
sed -i 's#android:label="wasl_chat"#android:label="وصل شات"#' $M
cat >> android/app/build.gradle.kts <<'KTS'

android {
    packaging {
        jniLibs { keepDebugSymbols += "**/*.so" }
    }
}
KTS
echo "== build"
flutter build apk --debug --target-platform android-arm64 2>&1 | tail -40
ls -la build/app/outputs/flutter-apk/ 2>/dev/null
