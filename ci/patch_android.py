"""Patches the freshly generated Flutter android/ folder: permissions, services, desugaring, label."""
import re, pathlib, sys

root = pathlib.Path('android/app')
mf = root / 'src/main/AndroidManifest.xml'
x = mf.read_text()

perms = """
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
"""
comps = """
        <service
            android:name="flutter.overlay.window.flutter_overlay_window.OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Floating moon companion shown over other apps"/>
        </service>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if 'OverlayService' not in x:
    x, n1 = re.subn(r'(<manifest[^>]*>)', lambda m: m.group(1) + perms, x, count=1)
    x, n2 = re.subn(r'</application>', comps + '    </application>', x, count=1)
    assert n1 == 1 and n2 == 1, 'manifest patch failed'
x = re.sub(r'android:label="[^"]*"', 'android:label="MoonPomo"', x, count=1)
mf.write_text(x)

# desugaring (needed by flutter_local_notifications)
for name in ('build.gradle.kts', 'build.gradle'):
    g = root / name
    if not g.exists():
        continue
    s = g.read_text()
    kts = name.endswith('.kts')
    flag = 'isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
    dep = ('\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
           if kts else
           "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n")
    s, n = re.subn(r'(compileOptions\s*\{)', lambda m: m.group(1) + '\n        ' + flag, s, count=1)
    assert n == 1, 'compileOptions not found in ' + name
    g.write_text(s + dep)
    print('patched', name)
    break
else:
    sys.exit('no build.gradle found')
print('ok')
