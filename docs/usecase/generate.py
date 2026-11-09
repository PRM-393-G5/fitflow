"""Generates FitFlow's use case diagram (draw.io + PlantUML) from one model.

Usage (from the repo root):
  python3 docs/usecase/generate.py docs/usecase.drawio docs/usecase.puml
"""
import sys
from xml.sax.saxutils import escape

UC_W, UC_H = 176, 56

STYLE = {
    'actor': 'shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;fillColor=#ffffff;strokeColor=#333333;',
    'system': 'shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;fillColor=#f5f5f5;strokeColor=#888888;fontColor=#555555;',
    'uc': 'ellipse;whiteSpace=wrap;html=1;fillColor=#EFEDFB;strokeColor=#6558D3;fontSize=12;',
    'abstract': 'ellipse;whiteSpace=wrap;html=1;fillColor=#EFEDFB;strokeColor=#6558D3;fontSize=12;fontStyle=2;',
    'boundary': 'rounded=0;whiteSpace=wrap;html=1;fillColor=none;verticalAlign=top;align=left;spacingLeft=12;spacingTop=4;fontSize=15;fontStyle=1;strokeColor=#333333;',
    'package': 'rounded=1;arcSize=2;whiteSpace=wrap;html=1;fillColor=#fafafa;verticalAlign=top;align=left;spacingLeft=10;fontStyle=1;dashed=1;strokeColor=#999999;fontColor=#555555;',
    'note': 'shape=note;whiteSpace=wrap;html=1;size=14;fillColor=#fff8dc;strokeColor=#c9b458;fontSize=11;align=left;spacingLeft=6;',
    'assoc': 'endArrow=none;html=1;strokeColor=#555555;',
    'include': 'endArrow=open;endSize=10;dashed=1;html=1;strokeColor=#6558D3;fontColor=#6558D3;fontSize=11;',
    'extend': 'endArrow=open;endSize=10;dashed=1;html=1;strokeColor=#c0562a;fontColor=#c0562a;fontSize=11;',
    'gen': 'endArrow=block;endFill=0;endSize=12;html=1;strokeColor=#333333;',
}


def uc(id, label, x, y, w=UC_W, h=UC_H):
    return ('uc', id, label, x, y, w, h)


def actor(id, label, x, y, system=False):
    return ('system' if system else 'actor', id, label, x, y, 36, 72)


def box(kind, id, label, x, y, w, h):
    return (kind, id, label, x, y, w, h)


# --- The model ---------------------------------------------------------------
# One page with the main use cases of both front ends, inside a single system
# boundary. Signing in is the only thing a Guest (not signed in) can do; User
# and Admin are signed in, so every other use case belongs to them.
#
# Edges: (kind, source, target, label). include/extend point from the base or
# extension as UML says: base ..> included, extension ..> base.

PAGES = []

# Columns and rows: each primary actor sits left of column 1, level with the
# rows it uses (Guest, then User, then Admin, so their lines never cross),
# and its lines never cross an ellipse; parent use cases sit in column 2 on
# a child's row; secondary actors sit right, level with the use cases they
# serve.
C1, C2 = 280, 620
W1, W2, H, STEP = 220, 220, 44, 58


def cases_in_column(ids_labels, y0):
    return [uc(id, label, C1, y0 + i * STEP, W1, H) for i, (id, label) in enumerate(ids_labels)]


def level(y0, i):
    """The top of an actor whose middle is level with row i of a column."""
    return round(y0 + i * STEP + H / 2 - 36)


# Sign out sits between the mobile and admin rows: User and Admin share it.
AUTH_Y0, MOBILE_Y0, SIGN_OUT_Y, ADMIN_Y0 = 80, 240, 800, 900
AUTH_CASES = [
    ('a3', 'Sign in with email & password'),
    ('a1', 'Sign in with Google'),
]
MOBILE_CASES = [
    ('m3', 'Browse workout library'),
    ('m2', 'Plan weekly schedule'),
    ('m4', 'Do a guided workout'),
    ('m5', 'Check exercise form'),
    ('m6', 'Plan nutrition & meals'),
    ('m7', 'Log a meal'),
    ('m8', 'Track body weight & profile'),
    ('m9', 'View progress & records'),
    ('m10', 'View session history'),
]
ADMIN_CASES = [
    ('d1', 'View statistics dashboard'),
    ('d2', 'Monitor AI usage'),
    ('d3', 'Manage users'),
    ('d4', 'Manage workout templates'),
]

PAGES.append({
    'name': 'Use cases',
    'title': 'FitFlow — Use cases',
    'shapes': [
        box('boundary', 'sys', 'FitFlow', 220, 20, 680, 1130),
        actor('guest', 'Guest', 90, level(AUTH_Y0, 0.5)),
        actor('user', 'User', 90, level(MOBILE_Y0, 4.5)),
        actor('admin', 'Admin', 90, level(ADMIN_Y0, 0.6)),
        actor('google', 'Google Sign-In', 1000, level(AUTH_Y0, 1.4), system=True),
        *cases_in_column(AUTH_CASES, AUTH_Y0),
        ('abstract', 'au', 'Authenticate', C2, AUTH_Y0, W2, H),
        *cases_in_column(MOBILE_CASES, MOBILE_Y0),
        uc('a2', 'Sign out', C1, SIGN_OUT_Y, W1, H),
        *cases_in_column(ADMIN_CASES, ADMIN_Y0),
    ],
    'edges': [
        ('assoc', 'guest', 'a3', ''),
        ('assoc', 'guest', 'a1', ''),
        *[('assoc', 'user', id, '') for id, _ in MOBILE_CASES],
        ('assoc', 'user', 'a2', ''),
        ('assoc', 'admin', 'a2', ''),
        *[('assoc', 'admin', id, '') for id, _ in ADMIN_CASES],
        ('gen', 'a3', 'au', ''),
        ('gen', 'a1', 'au', ''),
        ('assoc', 'a1', 'google', ''),
    ],
})


# --- draw.io -----------------------------------------------------------------

def drawio(pages):
    out = ['<mxfile host="app.diagrams.net" type="device">']
    for index, page in enumerate(pages):
        width = max(s[3] + s[5] for s in page['shapes']) + 60
        height = max(s[4] + s[6] for s in page['shapes']) + 80
        out.append(f'  <diagram name="{escape(page["name"], {chr(34): "&quot;"})}" id="fitflow-uc-{index + 1}">')
        out.append(f'    <mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="{width}" pageHeight="{height}" math="0" shadow="0">')
        out.append('      <root>')
        out.append('        <mxCell id="0" />')
        out.append('        <mxCell id="1" parent="0" />')
        for kind, id, label, x, y, w, h in page['shapes']:
            value = escape(label.replace('\n', '<br>'), {'"': '&quot;'})
            out.append(f'        <mxCell id="{id}" value="{value}" style="{STYLE[kind]}" vertex="1" parent="1">')
            out.append(f'          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />')
            out.append('        </mxCell>')
        shapes = {shape[1]: shape for shape in page['shapes']}
        is_actor = lambda id: shapes[id][0] in ('actor', 'system')
        for n, (kind, source, target, label) in enumerate(page['edges']):
            value = escape(label.replace('\n', '<br>'), {'"': '&quot;'})
            style = STYLE[kind]
            # An actor's line meets the use case at its near side (left or
            # right point), so fans of lines never cut through ellipses.
            if kind == 'assoc' and is_actor(source):
                side = 0 if shapes[source][3] < shapes[target][3] else 1
                style += f'entryX={side};entryY=0.5;entryDx=0;entryDy=0;'
            elif kind == 'assoc' and is_actor(target):
                side = 1 if shapes[target][3] > shapes[source][3] else 0
                style += f'exitX={side};exitY=0.5;exitDx=0;exitDy=0;'
            out.append(f'        <mxCell id="e{n}" value="{value}" style="{style}" edge="1" parent="1" source="{source}" target="{target}">')
            out.append('          <mxGeometry relative="1" as="geometry" />')
            out.append('        </mxCell>')
        out.append('      </root>')
        out.append('    </mxGraphModel>')
        out.append('  </diagram>')
    out.append('</mxfile>')
    return '\n'.join(out) + '\n'


# --- PlantUML ----------------------------------------------------------------

def plantuml(pages):
    out = []
    for page in pages:
        slug = page['name'].lower().replace(' & ', '-').replace(', ', '-').replace(' ', '-')
        out.append(f'@startuml fitflow-{slug}')
        out.append(f'title {page["title"]}')
        out.append('left to right direction')
        out.append('skinparam packageStyle rectangle')
        out.append('skinparam actorStyle awesome')
        out.append('skinparam usecase {\n  BackgroundColor #EFEDFB\n  BorderColor #6558D3\n}')
        plain = lambda label: label.replace('\n', '\\n')

        def case_label(shape):
            # An abstract use case is written in italics, as in draw.io.
            return f'//{plain(shape[2])}//' if shape[0] == 'abstract' else plain(shape[2])

        for kind, id, label, *_ in page['shapes']:
            if kind == 'actor':
                out.append(f'actor "{plain(label)}" as {id}')
            elif kind == 'system':
                out.append(f'actor "{plain(label)}" as {id} <<system>>')
        containers = [s for s in page['shapes'] if s[0] == 'package']

        def inside(shape, box):
            _, _, _, x, y, w, h = shape
            _, _, _, bx, by, bw, bh = box
            return bx <= x and by <= y and x + w <= bx + bw and y + h <= by + bh

        boundary = next(s for s in page['shapes'] if s[0] == 'boundary')
        out.append(f'rectangle "{plain(boundary[2])}" {{')
        cases = [s for s in page['shapes'] if s[0] in ('uc', 'abstract')]
        placed = set()
        for package in containers:
            out.append(f'  package "{plain(package[2])}" {{')
            for case in cases:
                if case[1] not in placed and inside(case, package):
                    out.append(f'    usecase "{case_label(case)}" as {case[1]}')
                    placed.add(case[1])
            out.append('  }')
        for case in cases:
            if case[1] not in placed:
                out.append(f'  usecase "{case_label(case)}" as {case[1]}')
        out.append('}')
        for kind, source, target, label in page['edges']:
            text = label.replace('«', '<<').replace('»', '>>').replace('\n', '\\n')
            if kind == 'assoc':
                out.append(f'{source} -- {target}')
            elif kind == 'gen':
                out.append(f'{source} --|> {target}')
            else:
                out.append(f'{source} ..> {target} : {text}')
        for kind, id, label, *_ in page['shapes']:
            if kind == 'note':
                out.append(f'note as {id}\n  {plain(label)}\nend note')
        out.append('@enduml')
        out.append('')
    return '\n'.join(out)


if __name__ == '__main__':
    with open(sys.argv[1], 'w', encoding='utf-8') as f:
        f.write(drawio(PAGES))
    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        f.write(plantuml(PAGES))
    print('pages:', len(PAGES), 'use cases:', sum(1 for p in PAGES for s in p['shapes'] if s[0] in ('uc', 'abstract')))
