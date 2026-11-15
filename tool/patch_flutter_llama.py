import os
import glob
import re

def patch_flutter_llama():
    print("=== Patching flutter_llama for CPU-only native build ===")
    pub_cache = os.path.expanduser("~/.pub-cache")
    pattern = os.path.join(pub_cache, "hosted", "pub.dev", "flutter_llama-*")
    matches = glob.glob(pattern)
    print(f"Found flutter_llama packages: {matches}")
    
    for base in matches:
        for root, dirs, files in os.walk(base):
            for file in files:
                filepath = os.path.join(root, file)
                if file.endswith((".txt", ".cmake", ".gradle", ".properties")):
                    try:
                        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()
                        
                        if "GGML_VULKAN" in content or "vulkan" in content.lower():
                            print(f"Inspecting file: {filepath}")
                            new_content = content
                            new_content = re.sub(r'GGML_VULKAN\s+ON', 'GGML_VULKAN OFF', new_content)
                            new_content = re.sub(r'option\s*\(\s*GGML_VULKAN\s+[^)]*\s+ON\s*\)', 'option(GGML_VULKAN "" OFF)', new_content, flags=re.IGNORECASE)
                            new_content = re.sub(r'set\s*\(\s*GGML_VULKAN\s+ON\s*\)', 'set(GGML_VULKAN OFF)', new_content, flags=re.IGNORECASE)
                            new_content = re.sub(r'-DGGML_VULKAN=ON', '-DGGML_VULKAN=OFF', new_content)
                            
                            # Also disable adding ggml-vulkan target if present
                            new_content = re.sub(r'add_subdirectory\s*\([^)]*vulkan[^)]*\)', '# disabled vulkan', new_content, flags=re.IGNORECASE)
                            
                            if new_content != content:
                                with open(filepath, "w", encoding="utf-8") as f:
                                    f.write(new_content)
                                print(f"Successfully patched {filepath} -> GGML_VULKAN=OFF")
                    except Exception as e:
                        print(f"Error checking {filepath}: {e}")

    print("=== flutter_llama patching complete ===")

if __name__ == "__main__":
    patch_flutter_llama()
