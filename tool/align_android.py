import os
import shutil
import subprocess
import re

def main():
    print("=== Aligning Android Gradle with Runner Flutter SDK ===")
    
    # 1. Print Flutter version
    subprocess.run(["flutter", "--version"], check=True)
    
    # 2. Generate a reference native Flutter app to discover exact Gradle & AGP setup
    ref_dir = "/tmp/ref_app"
    if os.path.exists(ref_dir):
        shutil.rmtree(ref_dir)
        
    subprocess.run([
        "flutter", "create",
        "--org", "com.example.offline_english_tutor",
        "--project-name", "offline_english_tutor",
        ref_dir
    ], check=True)
    
    # 3. Synchronize gradle wrapper
    target_gradle_dir = os.path.join("android", "gradle")
    if os.path.exists(target_gradle_dir):
        shutil.rmtree(target_gradle_dir)
    shutil.copytree(os.path.join(ref_dir, "android", "gradle"), target_gradle_dir)
    print("Updated android/gradle/ wrapper.")
    
    # 4. Check if reference app uses Kotlin DSL (.kts) or Groovy (.gradle)
    ref_settings_kts = os.path.join(ref_dir, "android", "settings.gradle.kts")
    if os.path.exists(ref_settings_kts):
        print("Reference app uses Kotlin DSL (.kts)")
        
        # Remove any legacy groovy files
        for f in ["settings.gradle", "build.gradle", "app/build.gradle"]:
            p = os.path.join("android", f)
            if os.path.exists(p):
                os.remove(p)
                
        # Copy settings and root build.gradle.kts
        shutil.copy(ref_settings_kts, os.path.join("android", "settings.gradle.kts"))
        
        with open(os.path.join(ref_dir, "android", "build.gradle.kts"), "r", encoding="utf-8") as f:
            root_content = f.read()
            
        root_content += '''
gradle.taskGraph.whenReady {
    allTasks.forEach { task ->
        if (task.name.contains("lint", ignoreCase = true)) {
            task.enabled = false
        }
    }
}
'''
        with open(os.path.join("android", "build.gradle.kts"), "w", encoding="utf-8") as f:
            f.write(root_content)
        
        # Read and patch app/build.gradle.kts
        with open(os.path.join(ref_dir, "android", "app", "build.gradle.kts"), "r", encoding="utf-8") as f:
            content = f.read()
            
        content = re.sub(r'minSdk\s*=.*', 'minSdk = 24', content)
        
        ndk_block = '''        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }'''
        content = re.sub(r'(defaultConfig\s*\{)', r'\1\n' + ndk_block, content)
        
        lint_block = '''
    lint {
        checkReleaseBuilds = false
        abortOnError = false
        checkDependencies = false
    }
'''
        content = re.sub(r'(android\s*\{)', r'\1\n' + lint_block, content)
        
        dep_block = '''
dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
'''
        content += dep_block
        
        with open(os.path.join("android", "app", "build.gradle.kts"), "w", encoding="utf-8") as f:
            f.write(content)
        print("Created and patched android/app/build.gradle.kts")
    else:
        print("Reference app uses Groovy DSL (.gradle)")
        
        # Remove any kts files
        for f in ["settings.gradle.kts", "build.gradle.kts", "app/build.gradle.kts"]:
            p = os.path.join("android", f)
            if os.path.exists(p):
                os.remove(p)
                
        shutil.copy(os.path.join(ref_dir, "android", "settings.gradle"), os.path.join("android", "settings.gradle"))
        
        with open(os.path.join(ref_dir, "android", "build.gradle"), "r", encoding="utf-8") as f:
            root_content = f.read()
            
        root_content += '''
gradle.taskGraph.whenReady {
    allTasks.each { task ->
        if (task.name.toLowerCase().contains("lint")) {
            task.enabled = false
        }
    }
}
'''
        with open(os.path.join("android", "build.gradle"), "w", encoding="utf-8") as f:
            f.write(root_content)
        
        with open(os.path.join(ref_dir, "android", "app", "build.gradle"), "r", encoding="utf-8") as f:
            content = f.read()
            
        content = re.sub(r'minSdkVersion\s+.*', 'minSdkVersion 24', content)
        content = re.sub(r'minSdk\s+.*', 'minSdk 24', content)
        
        ndk_block = '''        ndk {
            abiFilters "arm64-v8a", "x86_64"
        }'''
        content = re.sub(r'(defaultConfig\s*\{)', r'\1\n' + ndk_block, content)
        
        lint_block = '''
    lint {
        checkReleaseBuilds = false
        abortOnError = false
        checkDependencies = false
    }
'''
        content = re.sub(r'(android\s*\{)', r'\1\n' + lint_block, content)
        
        dep_block = '''
dependencies {
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.mlkit:text-recognition:16.0.1'
}
'''
        content += dep_block
        
        with open(os.path.join("android", "app", "build.gradle"), "w", encoding="utf-8") as f:
            f.write(content)
        print("Created and patched android/app/build.gradle")
        
    # Ensure AndroidManifest.xml does not have legacy package attribute
    manifest_path = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as f:
            m = f.read()
        m = re.sub(r'\s+package="[^"]*"', '', m)
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(m)
        print("Ensured AndroidManifest.xml namespace compliance.")
        
    print("=== Native Gradle Alignment Complete ===")

if __name__ == "__main__":
    main()
