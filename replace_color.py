#!/usr/bin/env python3
import os

filepath = r'c:\Users\MAHEK\liquid_logistics\lib\main.dart'

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the color
new_content = content.replace('const Color(0xFF0F172A)', 'const Color(0xFF0A1628)')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Color replacement completed!")
