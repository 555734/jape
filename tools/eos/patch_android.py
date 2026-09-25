"""Godot の Android ビルドテンプレート(android/build)に、EOS SDK を組み込む変更を入れる。

CI で android_source.zip を展開した直後に1回だけ実行する(何度実行しても同じ結果になる)。
EOSG の README「Exporting for Android」と EOS Android SDK の要件に合わせた変更:
  - EOS SDK(eossdk-StaticSTDC-release.aar)と、それが使う AndroidX ライブラリを依存に追加
  - EOS SDK 1.18 以降が必要とする Java の desugaring を有効にする
  - EOS SDK が参照する文字列リソース eos_login_protocol_scheme を定義する(Client ID から作る。秘密ではない)
  - 起動時に libEOSSDK を読み込み、EOSSDK.init(activity) を呼ぶ
使い方: python3 tools/eos/patch_android.py <android/build のパス>   (環境変数 EOS_CLIENT_ID があれば使う)
"""
import os
import pathlib
import re
import sys

MARK = "// jape: EOS SDK"

build = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "android/build")


def patch(path: pathlib.Path, fn) -> None:
    text = path.read_text(encoding="utf-8")
    if MARK in text:
        print(f"{path}: 変更済み")
        return
    new = fn(text)
    if new == text:
        sys.exit(f"{path}: 変更箇所が見つかりません(Godot のテンプレートが変わった可能性)")
    path.write_text(new, encoding="utf-8")
    print(f"{path}: 変更しました")


def insert_after(text: str, anchor: str, addition: str) -> str:
    i = text.find(anchor)
    if i < 0:
        sys.exit(f"見つかりません: {anchor}")
    j = text.index("\n", i) + 1
    return text[:j] + addition + text[j:]


def gradle(text: str) -> str:
    text = insert_after(text, 'implementation "androidx.core:core-splashscreen:', f"""
    {MARK}
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'
    implementation 'androidx.appcompat:appcompat:1.5.1'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'androidx.security:security-crypto:1.0.0'
    implementation 'androidx.browser:browser:1.4.0'
    implementation 'androidx.webkit:webkit:1.7.0'
    implementation files('../../addons/epic-online-services-godot/bin/android/eossdk-StaticSTDC-release.aar')
""")
    text = insert_after(text, "compileOptions {", "        coreLibraryDesugaringEnabled true\n")
    client_id = re.sub(r"[^A-Za-z0-9]", "", os.environ.get("EOS_CLIENT_ID", "")) or "unset"
    text = insert_after(text, "missingDimensionStrategy 'products', 'template'",
                        f'        resValue("string", "eos_login_protocol_scheme", "eos.{client_id.lower()}")\n')
    return text


def java(text: str) -> str:
    text = insert_after(text, "import org.godotengine.godot.GodotActivity;",
                        "import com.epicgames.mobile.eossdk.EOSSDK;\n")
    text = insert_after(text, "public class GodotApp extends GodotActivity {", f"""\t{MARK}
\tstatic {{
\t\tSystem.loadLibrary("EOSSDK");
\t}}

""")
    text = insert_after(text, "public void onCreate(Bundle savedInstanceState) {", "\t\tEOSSDK.init(this);\n")
    return text


patch(build / "build.gradle", gradle)
java_files = list(build.rglob("GodotApp.java"))
if len(java_files) != 1:
    sys.exit(f"GodotApp.java が1つに決まりません: {java_files}")
patch(java_files[0], java)
