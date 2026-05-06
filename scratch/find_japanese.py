import os
import re

# Japanese character ranges
# Hiragana: \u3040-\u309F
# Katakana: \u30A0-\u30FF
# Kanji: \u4E00-\u9FFF

jp_regex = re.compile(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]+')

def scan_directory(path):
    for root, dirs, files in os.walk(path):
        if '.git' in root or '.xcodeproj' in root or '.xcassets' in root or 'DerivedData' in root:
            continue
        for file in files:
            if file.endswith('.swift'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        for i, line in enumerate(f, 1):
                            if jp_regex.search(line):
                                # Skip lines with comments if they only have Japanese in comments
                                # But actually it's better to show them and filter manually
                                print(f"{file_path}:{i}: {line.strip()}")
                except Exception as e:
                    pass

if __name__ == "__main__":
    scan_directory(".")
