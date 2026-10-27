"""Generates FitFlow's use case diagrams (draw.io + PlantUML) from one model.

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
# Edges: (kind, source, target, label). include/extend point from the base or
# extension as UML says: base ..> included, extension ..> base.

PAGES = []

# Columns and rows: the primary actor sits left of column 1, which holds every
# use case it uses, so its lines never cross an ellipse; included, extending
# and child use cases sit to the right on their base's row where possible;
# secondary actors sit right, level with the use case they serve.
C1, C2, C3, C4 = 280, 600, 900, 1180


def cases_in_column(ids_labels, x, y0, step, w=240, h=46):
    return [uc(id, label, x, y0 + i * step, w, h) for i, (id, label) in enumerate(ids_labels)]


APP_CASES = [
    ('o1', 'Sign in with Google'),
    ('o2', 'Plan workouts'),
    ('o3', 'Do a guided workout'),
    ('o4', 'Check exercise form'),
    ('o5', 'Get AI coaching'),
    ('o6', 'Plan nutrition &amp; log meals'),
    ('o7', 'Track progress &amp; body metrics'),
    ('o8', 'Manage settings &amp; reminders'),
    ('o9', 'Back up &amp; sync data'),
]
ADMIN_CASES = [
    ('a1', 'Sign in (email &amp; password)'),
    ('a2', 'View statistics dashboard'),
    ('a3', 'Manage users'),
    ('a4', 'Manage workout templates'),
    ('a5', 'Monitor AI usage'),
]
row = lambda i, y0=100, step=62: y0 + i * step + 23 - 36  # actor y level with row i

PAGES.append({
    'name': 'Overview',
    'title': 'FitFlow — Use cases (overview)',
    'shapes': [
        box('boundary', 'sys', 'FitFlow system', 220, 20, 620, 1050),
        box('package', 'pkgApp', 'Mobile app (Flutter) + FitFlow API', 240, 60, 580, 610),
        box('package', 'pkgAdmin', 'Admin web (React) + admin API', 240, 700, 580, 350),
        actor('user', 'User\n(trainee)', 90, 330),
        actor('admin', 'Admin', 90, 840),
        actor('google', 'Google\nSign-In', 960, row(0), system=True),
        actor('camera', 'Camera +\nML Kit Pose', 960, row(2.5), system=True),
        actor('openai', 'OpenAI\n(GPT models)', 960, row(4.6), system=True),
        actor('os', 'Device OS\n(notifications, share)', 960, row(7), system=True),
        *cases_in_column(APP_CASES, 330, 100, 62),
        *cases_in_column(ADMIN_CASES, 330, 750, 62),
    ],
    'edges': [
        *[('assoc', 'user', id, '') for id, _ in APP_CASES],
        *[('assoc', 'admin', id, '') for id, _ in ADMIN_CASES],
        ('assoc', 'o1', 'google', ''),
        ('assoc', 'o4', 'camera', ''),
        ('assoc', 'o5', 'openai', ''),
        ('assoc', 'o6', 'openai', ''),
        ('assoc', 'o8', 'os', ''),
    ],
})

PAGES.append({
    'name': 'Account & data',
    'title': 'FitFlow — Account & data',
    'shapes': [
        box('boundary', 'sys', 'Mobile app + FitFlow API', 220, 20, 860, 620),
        actor('user', 'User', 90, 260),
        actor('google', 'Google\nSign-In', 1160, 72, system=True),
        uc('s1', 'Sign in with Google', C1, 80, 200),
        uc('s2', 'Sign out', C1, 200, 200),
        uc('s3', 'Delete account', C1, 330, 200),
        uc('s4', 'Back up data (JSON)', C1, 470, 200),
        uc('s7', 'See “account locked” message', C2, 36, 220),
        uc('s5', 'Sync data with the cloud', C2, 150, 220),
        uc('s6', 'Re-authenticate with Google', C2, 330, 220),
        uc('s8', 'Export data', C2, 430, 180, 46),
        uc('s9', 'Import data', C2, 520, 180, 46),
        box('note', 'n1', 'Sign-in is required. Data stays cached on the phone, so it works offline; edits wait in an outbox until they reach the server.', 860, 440, 200, 110),
    ],
    'edges': [
        ('assoc', 'user', 's1', ''),
        ('assoc', 'user', 's2', ''),
        ('assoc', 'user', 's3', ''),
        ('assoc', 'user', 's4', ''),
        ('assoc', 's1', 'google', ''),
        ('assoc', 's6', 'google', ''),
        ('include', 's1', 's5', '«include»\ndownload account data'),
        ('include', 's2', 's5', '«include»\nupload pending changes'),
        ('include', 's3', 's6', '«include»'),
        ('extend', 's7', 's1', '«extend»\n[locked by an admin]'),
        ('gen', 's8', 's4', ''),
        ('gen', 's9', 's4', ''),
    ],
})

PAGES.append({
    'name': 'Workout planning',
    'title': 'FitFlow — Workout planning',
    'shapes': [
        box('boundary', 'sys', 'Mobile app + FitFlow API', 220, 20, 660, 520),
        actor('user', 'User', 90, 250),
        actor('openai', 'OpenAI', 1000, 330 + 28 - 36, system=True),
        uc('p1', 'Complete onboarding\n(goal, level)', C1, 60, 220),
        uc('p2', 'View today’s workout', C1, 150, 220),
        uc('p3', 'Browse workout library', C1, 240, 220),
        uc('p4', 'Build custom workout', C1, 330, 220),
        uc('p5', 'Plan weekly schedule', C1, 420, 220),
        uc('p6', 'View workout details', C2, 240, 220),
        uc('p7', 'Generate workout with AI', C2, 330, 220),
    ],
    'edges': [
        *[('assoc', 'user', id, '') for id in ('p1', 'p2', 'p3', 'p4', 'p5')],
        ('extend', 'p6', 'p3', '«extend»'),
        ('extend', 'p7', 'p4', '«extend»'),
        ('assoc', 'p7', 'openai', ''),
    ],
})

PAGES.append({
    'name': 'Training & form check',
    'title': 'FitFlow — Training & AI form check',
    'shapes': [
        box('boundary', 'sys', 'Mobile app + FitFlow API', 220, 20, 1180, 760),
        actor('user', 'User', 90, 360),
        actor('camera', 'Camera +\nML Kit Pose', 1500, 498 - 36, system=True),
        actor('openai', 'OpenAI', 1500, 708 - 36, system=True),
        uc('t1', 'Do a guided workout', C1, 210, 210),
        uc('t2', 'See progressive-overload hint', C2 + 40, 60, 230),
        uc('t3', 'Save session to history', C2 + 40, 150, 230),
        uc('t4', 'Resume saved draft', C2 + 40, 270, 230),
        uc('t5', 'Count sets with camera', C2 + 40, 380, 230),
        uc('t6', 'Hands-free mode\n(spoken countdowns)', C3 + 120, 380, 230),
        uc('f1', 'Check exercise form\n(7 exercises)', C1, 560, 210),
        uc('f3', 'Count reps / hold\n&amp; score form', C2 + 40, 560, 230),
        uc('f2', 'Analyze pose in real time', C3 + 120, 470, 230),
        uc('f4', 'Review squat set with AI', C2 + 40, 680, 230),
    ],
    'edges': [
        ('assoc', 'user', 't1', ''),
        ('assoc', 'user', 'f1', ''),
        ('include', 't1', 't2', '«include»'),
        ('include', 't1', 't3', '«include»'),
        ('extend', 't4', 't1', '«extend»\n[draft saved]'),
        ('extend', 't5', 't1', '«extend»\n[camera-checkable set]'),
        ('gen', 't6', 't5', ''),
        ('include', 't5', 'f2', '«include»'),
        ('include', 'f1', 'f3', '«include»'),
        ('include', 'f3', 'f2', '«include»'),
        ('assoc', 'f2', 'camera', ''),
        ('extend', 'f4', 'f1', '«extend»\n[squat]'),
        ('assoc', 'f4', 'openai', ''),
    ],
})

PAGES.append({
    'name': 'Nutrition & body metrics',
    'title': 'FitFlow — Nutrition & body metrics',
    'shapes': [
        box('boundary', 'sys', 'Mobile app + FitFlow API', 220, 20, 940, 600),
        actor('user', 'User', 90, 260),
        actor('openai', 'OpenAI', 1260, 190, system=True),
        uc('n1', 'View nutrition targets', C1, 60, 220),
        uc('n2', 'Update body profile', C1, 150, 220),
        uc('n3', 'Log body weight\n&amp; view trend', C1, 240, 220),
        uc('n5', 'Log a meal', C1, 420, 220),
        uc('n4', 'Generate AI meal plan', C2, 60, 220),
        uc('n6', 'Log from food photo', C2, 330, 220, 46),
        uc('n7', 'Log manually', C2, 420, 220, 46),
        uc('n8', 'Log from meal plan', C2, 510, 220, 46),
        uc('n9', 'Analyze food photo with AI', C3, 325, 220),
        box('note', 'n10', 'Targets follow safety limits: calorie floors, no deficit when underweight, none under 18.', 900, 450, 220, 90),
    ],
    'edges': [
        *[('assoc', 'user', id, '') for id in ('n1', 'n2', 'n3', 'n5')],
        ('extend', 'n4', 'n1', '«extend»'),
        ('assoc', 'n4', 'openai', ''),
        ('gen', 'n6', 'n5', ''),
        ('gen', 'n7', 'n5', ''),
        ('gen', 'n8', 'n5', ''),
        ('include', 'n6', 'n9', '«include»'),
        ('assoc', 'n9', 'openai', ''),
    ],
})

PAGES.append({
    'name': 'Progress & settings',
    'title': 'FitFlow — Progress & settings',
    'shapes': [
        box('boundary', 'sys', 'Mobile app + FitFlow API', 220, 20, 660, 620),
        actor('user', 'User', 90, 300),
        actor('os', 'Device OS\n(notifications, share)', 1000, 300, system=True),
        uc('g1', 'View progress dashboard', C1, 60, 220),
        uc('g2', 'View muscle map', C1, 160, 220),
        uc('g3', 'View achievements &amp; streak', C1, 260, 220),
        uc('g4', 'View session history', C1, 360, 220),
        uc('g6', 'Set workout reminders', C1, 480, 220),
        uc('g7', 'Change theme &amp; units', C1, 570, 220, 46),
        uc('g5', 'Share summary card', C2, 60, 220),
        uc('g9', 'See exercises behind a muscle', C2, 160, 220),
        uc('g8', 'Edit or delete a session', C2, 360, 220),
    ],
    'edges': [
        *[('assoc', 'user', id, '') for id in ('g1', 'g2', 'g3', 'g4', 'g6', 'g7')],
        ('extend', 'g5', 'g1', '«extend»'),
        ('extend', 'g9', 'g2', '«extend»'),
        ('extend', 'g8', 'g4', '«extend»'),
        ('assoc', 'g5', 'os', ''),
        ('assoc', 'g6', 'os', ''),
    ],
})

PAGES.append({
    'name': 'Admin web',
    'title': 'FitFlow — Admin web',
    'shapes': [
        box('boundary', 'sys', 'Admin web (React) + admin API', 220, 20, 1220, 820),
        actor('admin', 'Admin', 90, 360),
        uc('d0', 'Sign in (email &amp; password)', C1, 40, 220),
        uc('d1', 'View statistics dashboard', C1, 140, 220),
        uc('d2', 'Monitor AI usage', C1, 240, 220),
        uc('m1', 'Manage users', C1, 380, 220),
        uc('t0', 'Manage workout templates', C1, 620, 220),
        uc('d4', 'View chart as table', C2, 90, 200, 46),
        uc('d3', 'Choose date range', C2, 190, 200, 46),
        uc('m2', 'Search &amp; filter users', C2, 330, 220, 46),
        uc('m3', 'View user details', C2, 430, 220, 46),
        uc('m4', 'Lock / unlock account', C3, 400, 220, 46),
        uc('m5', 'Delete account &amp; data', C3, 480, 220, 46),
        uc('m6', 'Confirm by typing the email', C4, 480, 220, 46),
        uc('t1', 'Create template', C2, 550, 200, 44),
        uc('t2', 'Edit template', C2, 615, 200, 44),
        uc('t3', 'Reorder templates', C2, 680, 200, 44),
        uc('t4', 'Delete template', C2, 745, 200, 44),
        box('note', 'n1', 'Every admin use case needs a signed-in admin. Locking signs the user out everywhere and blocks sign-in, sync and AI.', 1000, 120, 240, 110),
    ],
    'edges': [
        *[('assoc', 'admin', id, '') for id in ('d0', 'd1', 'd2', 'm1', 't0')],
        ('extend', 'd4', 'd1', '«extend»'),
        ('include', 'd1', 'd3', '«include»'),
        ('include', 'd2', 'd3', '«include»'),
        ('include', 'm1', 'm2', '«include»'),
        ('extend', 'm3', 'm1', '«extend»'),
        ('extend', 'm4', 'm3', '«extend»'),
        ('extend', 'm5', 'm3', '«extend»'),
        ('include', 'm5', 'm6', '«include»'),
        *[('gen', id, 't0', '') for id in ('t1', 't2', 't3', 't4')],
    ],
})


# --- draw.io -----------------------------------------------------------------

def drawio(pages):
    out = ['<mxfile host="app.diagrams.net" type="device">']
    for index, page in enumerate(pages):
        width = max(s[3] + s[5] for s in page['shapes']) + 60
        height = max(s[4] + s[6] for s in page['shapes']) + 80
        out.append(f'  <diagram name="{escape(page["name"])}" id="fitflow-uc-{index + 1}">')
        out.append(f'    <mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="{width}" pageHeight="{height}" math="0" shadow="0">')
        out.append('      <root>')
        out.append('        <mxCell id="0" />')
        out.append('        <mxCell id="1" parent="0" />')
        for kind, id, label, x, y, w, h in page['shapes']:
            value = escape(label.replace('&amp;', '&').replace('\n', '<br>'), {'"': '&quot;'})
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
        out.append(f'@startuml fitflow-usecase-{slug}')
        out.append(f'title {page["title"]}')
        out.append('left to right direction')
        out.append('skinparam packageStyle rectangle')
        out.append('skinparam actorStyle awesome')
        out.append('skinparam usecase {\n  BackgroundColor #EFEDFB\n  BorderColor #6558D3\n}')
        shapes = {s[1]: s for s in page['shapes']}
        plain = lambda label: label.replace('&amp;', '&').replace('\n', '\\n')
        for kind, id, label, *_ in page['shapes']:
            if kind == 'actor':
                out.append(f'actor "{plain(label)}" as {id}')
            elif kind == 'system':
                out.append(f'actor "{plain(label)}" as {id} <<system>>')
        containers = [s for s in page['shapes'] if s[0] in ('package',)]

        def inside(shape, box):
            _, _, _, x, y, w, h = shape
            _, _, _, bx, by, bw, bh = box
            return bx <= x and by <= y and x + w <= bx + bw and y + h <= by + bh

        boundary = next(s for s in page['shapes'] if s[0] == 'boundary')
        out.append(f'rectangle "{plain(boundary[2])}" {{')
        cases = [s for s in page['shapes'] if s[0] == 'uc']
        placed = set()
        for package in containers:
            out.append(f'  package "{plain(package[2])}" {{')
            for case in cases:
                if case[1] not in placed and inside(case, package):
                    out.append(f'    usecase "{plain(case[2])}" as {case[1]}')
                    placed.add(case[1])
            out.append('  }')
        for case in cases:
            if case[1] not in placed:
                out.append(f'  usecase "{plain(case[2])}" as {case[1]}')
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
    with open(sys.argv[1], 'w') as f:
        f.write(drawio(PAGES))
    with open(sys.argv[2], 'w') as f:
        f.write(plantuml(PAGES))
    print('pages:', len(PAGES), 'use cases:', sum(1 for p in PAGES for s in p['shapes'] if s[0] == 'uc'))
