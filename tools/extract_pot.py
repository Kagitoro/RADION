#!/usr/bin/env python3
"""Regenerates locale/messages.pot from the game's sources.

Collects:
  * string literals passed to tr(...) / TranslationServer.translate(...) in scripts/ and ui/ (recursive)
  * Russian strings inside `const` arrays/dictionaries (translated where displayed)
  * text, title, dialog, button, placeholder and tooltip properties in ui/**/*.tscn
    (Godot auto-translates them)
  * object labels and room names from assets/layout.json (translated in the HUD)

Usage (from the project root):  python3 tools/extract_pot.py
"""
import collections
import glob
import json
import re

LITERAL = r'"((?:[^"\\\n]|\\.)*)"'
CYRILLIC = re.compile('[А-Яа-яЁё]')


def collect():
    refs = collections.OrderedDict()

    def add(text, where):
        refs.setdefault(text, []).append(where)

    for path in sorted(glob.glob('scripts/**/*.gd', recursive=True) + glob.glob('ui/**/*.gd', recursive=True)):
        in_const, depth = False, 0
        for number, line in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
            for match in re.finditer(r'(?:tr|translate)\(' + LITERAL, line):
                add(match.group(1), f'{path}:{number}')
            if re.match(r'^const ', line):
                in_const, depth = True, 0
            if in_const:
                depth += line.count('[') + line.count('{') - line.count(']') - line.count('}')
                for match in re.finditer(LITERAL, line):
                    if CYRILLIC.search(match.group(1)):
                        add(match.group(1), f'{path}:{number}')
                if depth <= 0:
                    in_const = False

    for path in sorted(glob.glob('ui/**/*.tscn', recursive=True)):
        text = open(path, encoding='utf-8').read()
        for match in re.finditer(r'^(?:text|title|dialog_text|ok_button_text|cancel_button_text|placeholder_text|tooltip_text) = "((?:[^"\\]|\\.)*)"', text, flags=re.M | re.S):
            add(match.group(1).replace('\n', '\\n'), path)

    layout = json.load(open('assets/layout.json', encoding='utf-8'))
    for row in layout.get('objects', []) + layout.get('inventory', []):
        if isinstance(row, dict) and CYRILLIC.search(str(row.get('label', ''))):
            add(str(row['label']).replace('"', '\\"'), 'assets/layout.json')
    for room in layout.get('rooms', {}).values():
        if isinstance(room, dict) and CYRILLIC.search(str(room.get('name', ''))):
            add(str(room['name']).replace('"', '\\"'), 'assets/layout.json')
    return refs


def main():
    refs = collect()
    out = [
        '# Translation template for Late Set. Source language: Russian.',
        '# Create <lang>.po from this file (e.g. with Poedit), then add it under',
        '# Project Settings > Localization > Translations.',
        'msgid ""',
        'msgstr ""',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '',
    ]
    for text, where in refs.items():
        out.append('#: ' + ' '.join(sorted(set(where))[:4]))
        out.append(f'msgid "{text}"')
        out.append('msgstr ""')
        out.append('')
    with open('locale/messages.pot', 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(out))
    print(f'{len(refs)} messages -> locale/messages.pot')


if __name__ == '__main__':
    main()
