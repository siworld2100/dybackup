# -*- coding: utf-8 -*-
"""生成 App 图标：白底 + 蓝色 + 机器人 + 下载箭头融合。

用超采样（4x）+ LANCZOS 缩放得到抗锯齿效果，保证各密度都清晰。
"""
import os
import math
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
os.makedirs(OUT, exist_ok=True)

SS = 4  # 超采样倍数

# 配色：蓝色系
BLUE = (37, 99, 235)        # #2563EB 主蓝
BLUE_DARK = (29, 78, 216)   # #1D4ED8 深蓝
BLUE_LIGHT = (96, 165, 250) # #60A5FA 浅蓝
WHITE = (255, 255, 255)

# 方案 D（bilibili TV 风格）：黑底 + 抖音红
BLACK = (15, 15, 15)        # #0F0F0F 近黑底
RED = (254, 44, 85)         # #FE2C55 抖音红

# 方案 E（参考图风格）：深蓝黑底 + 玫红圆角箭头 + 青色托盘
NAVY = (28, 33, 46)         # #1C212E 底色
PINK = (246, 62, 92)        # #F63E5C 箭头
CYAN = (52, 224, 200)       # #34E0C8 托盘

FONT_PATH = r"C:\Windows\Fonts\msyhbd.ttc"  # 微软雅黑 Bold


def canvas(size):
    """返回 (image, draw)，坐标按 1024 设计稿等比映射。"""
    px = size * SS
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    return img, d, px / 1024.0


def rr(d, box, r, fill=None, outline=None, width=0):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def design_a(d, s, bg=True):
    """方案 A：机器人头 + 下方下载箭头（最简洁，缩到 48px 仍清晰）"""
    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=WHITE)

    cx = P(512)
    # 天线
    d.line([cx, P(196), cx, P(268)], fill=BLUE, width=int(P(30)))
    d.ellipse([cx - P(46), P(150), cx + P(46), P(242)], fill=BLUE)

    # 头部（圆角方）
    head = [P(248), P(268), P(776), P(636)]
    rr(d, head, P(120), fill=BLUE)

    # 眼睛（白色圆角）
    er = P(56)
    for ex in (P(406), P(618)):
        d.ellipse([ex - er, P(388) - er, ex + er, P(388) + er], fill=WHITE)

    # 嘴（白色横条）
    rr(d, [P(432), P(524), P(592), P(568)], P(22), fill=WHITE)

    # 两侧耳朵
    for x0 in (P(176), P(782)):
        rr(d, [x0, P(392), x0 + P(66), P(512)], P(33), fill=BLUE_LIGHT)

    # 下载箭头（头顶下方的箭头，压在头部下缘）
    acx = P(512)
    top, bot, hw = P(700), P(880), P(112)
    # 竖杆
    d.rectangle([acx - P(34), top, acx + P(34), bot - P(64)], fill=BLUE_DARK)
    # 箭头三角
    d.polygon(
        [(acx - hw, bot - P(96)), (acx + hw, bot - P(96)), (acx, bot)],
        fill=BLUE_DARK,
    )
    # 底部托盘
    rr(d, [P(320), P(928), P(704), P(972)], P(22), fill=BLUE_LIGHT)


def design_b(d, s, bg=True):
    """方案 B：箭头本身就构成机器人的身体（融合更彻底）"""
    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=WHITE)

    cx = P(512)
    d.line([cx, P(180), cx, P(248)], fill=BLUE, width=int(P(28)))
    d.ellipse([cx - P(44), P(136), cx + P(44), P(224)], fill=BLUE)

    # 头部
    rr(d, [P(252), P(248), P(772), P(600)], P(110), fill=BLUE)
    er = P(54)
    for ex in (P(410), P(614)):
        d.ellipse([ex - er, P(362) - er, ex + er, P(362) + er], fill=WHITE)
    rr(d, [P(436), P(492), P(588), P(534)], P(21), fill=WHITE)
    for x0 in (P(182), P(776)):
        rr(d, [x0, P(368), x0 + P(64), P(482)], P(32), fill=BLUE_LIGHT)

    # 箭头整体作为身体，比 A 更大更饱满
    acx = P(512)
    top, bot, hw = P(648), P(936), P(168)
    d.rectangle([acx - P(46), top, acx + P(46), bot - P(96)], fill=BLUE_DARK)
    d.polygon(
        [(acx - hw, bot - P(148)), (acx + hw, bot - P(148)), (acx, bot)],
        fill=BLUE_DARK,
    )


def design_c(d, s, bg=True):
    """方案 C：头部内嵌箭头（最紧凑，适合小尺寸）"""
    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=WHITE)

    cx = P(512)
    d.line([cx, P(182), cx, P(250)], fill=BLUE, width=int(P(30)))
    d.ellipse([cx - P(46), P(138), cx + P(46), P(226)], fill=BLUE)

    rr(d, [P(206), P(250), P(818), P(848)], P(150), fill=BLUE)
    for x0 in (P(134), P(824)):
        rr(d, [x0, P(420), x0 + P(66), P(560)], P(33), fill=BLUE_LIGHT)

    # 头部中间挖一圈白色，内嵌深蓝箭头
    er = P(56)
    for ex in (P(386), P(638)):
        d.ellipse([ex - er, P(432) - er, ex + er, P(432) + er], fill=WHITE)

    acx = P(512)
    top, bot, hw = P(536), P(776), P(104)
    d.rectangle([acx - P(32), top, acx + P(32), bot - P(70)], fill=WHITE)
    d.polygon(
        [(acx - hw, bot - P(104)), (acx + hw, bot - P(104)), (acx, bot)],
        fill=WHITE,
    )


def design_d(d, s, bg=True):
    """方案 D：黑底圆角方 + 红色「抖」字 + 红色下载箭头（bilibili TV 风格）"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=BLACK)

    # 「抖」字：左侧大字，垂直居中（baseline 需留出字高，避免顶部裁切）
    font = ImageFont.truetype(FONT_PATH, int(P(440)))
    d.text((P(80), P(676)), "抖", font=font, fill=RED, anchor="ls")

    # 下载箭头：右侧，与文字视觉中线对齐
    acx = P(762)
    top, bot, hw = P(356), P(676), P(126)
    d.rectangle([acx - P(44), top, acx + P(44), bot - P(104)], fill=RED)
    d.polygon(
        [(acx - hw, bot - P(140)), (acx + hw, bot - P(140)), (acx, bot)],
        fill=RED,
    )
    # 箭头下横线（下载符号的托底线）
    rr(d, [acx - hw, bot + P(34), acx + hw, bot + P(78)], P(22), fill=RED)


def _rounded_arrow(d, P, cx, top, bottom, hw, color):
    """参考图风格的下载箭头：圆头竖杆 + 圆角三角头，实心。"""
    head_h = (bottom - top) * 0.52
    shaft_w = hw * 0.62
    shaft_bottom = bottom - head_h
    edge = (bottom - top) * 0.055  # 描边宽度，用来把三角的角滚圆

    # 竖杆（顶端圆头）
    rr(
        d,
        [cx - shaft_w / 2, top, cx + shaft_w / 2, shaft_bottom + shaft_w / 2],
        shaft_w / 2,
        fill=color,
    )

    # 三角头：先填充，再沿三条边走粗线把尖角滚圆
    pts = [(cx - hw, shaft_bottom), (cx + hw, shaft_bottom), (cx, bottom)]
    d.polygon(pts, fill=color)
    d.line(pts + [pts[0]], fill=color, width=int(edge), joint="curve")
    r = edge / 2
    for px, py in pts:
        d.ellipse([px - r, py - r, px + r, py + r], fill=color)


def _tray(d, P, cx, y, hw, h, color):
    rr(d, [cx - hw, y, cx + hw, y + h], h / 2, fill=color)


def design_e1(d, s, bg=True):
    """E1 竖排：抖 在上，箭头+托盘 在下（最贴近参考图的居中构图）"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(280)))
    d.text((P(512), P(360)), "抖", font=font, fill=PINK, anchor="mm")

    _rounded_arrow(d, P, P(512), P(470), P(800), P(150), PINK)
    _tray(d, P, P(512), P(858), P(210), P(56), CYAN)


def design_e2(d, s, bg=True):
    """E2 左右排：抖 在左，箭头+托盘 在右（延续方案 D 的构图）"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(430)))
    d.text((P(78), P(668)), "抖", font=font, fill=PINK, anchor="ls")

    _rounded_arrow(d, P, P(760), P(330), P(668), P(128), PINK)
    _tray(d, P, P(760), P(716), P(182), P(50), CYAN)


def design_e3(d, s, bg=True):
    """E3 水印字：大号暗色「抖」铺底，粉色箭头叠在上面（层次感最强）"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    dim = (52, 60, 80)  # 比底色亮一档的暗蓝灰
    font = ImageFont.truetype(FONT_PATH, int(P(640)))
    d.text((P(512), P(470)), "抖", font=font, fill=dim, anchor="mm")

    _rounded_arrow(d, P, P(512), P(250), P(760), P(170), PINK)
    _tray(d, P, P(512), P(830), P(240), P(58), CYAN)


def design_f1(d, s, bg=True):
    """F1 白字粉箭：抖用白色拉开层次，箭头保持玫红主色"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(390)))
    d.text((P(60), P(640)), "抖", font=font, fill=WHITE, anchor="ls")

    _rounded_arrow(d, P, P(772), P(270), P(668), P(136), PINK)
    _tray(d, P, P(772), P(716), P(188), P(52), CYAN)


def design_f2(d, s, bg=True):
    """F2 箭上字下：箭头为绝对主体，抖做底部字标，托盘夹在中间"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    _rounded_arrow(d, P, P(512), P(170), P(610), P(175), PINK)
    _tray(d, P, P(512), P(660), P(238), P(54), CYAN)

    font = ImageFont.truetype(FONT_PATH, int(P(270)))
    d.text((P(512), P(856)), "抖", font=font, fill=WHITE, anchor="mm")


def design_f3(d, s, bg=True):
    """F3 角标徽章：箭头完整保留，抖收进右下角小圆徽章里"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    _rounded_arrow(d, P, P(500), P(210), P(640), P(158), PINK)
    _tray(d, P, P(500), P(690), P(220), P(52), CYAN)

    # 右下角徽章：底色与背景同色 + 青色描边，避免三个色块打架
    cx, cy, r = P(800), P(800), P(126)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=NAVY,
              outline=CYAN, width=int(P(14)))
    font = ImageFont.truetype(FONT_PATH, int(P(150)))
    d.text((cx, cy - P(4)), "抖", font=font, fill=PINK, anchor="mm")


def design_f4(d, s, bg=True):
    """F4 描边水印：抖用描边字做底纹，实心箭头压在上面，层次不乱"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(760)))
    d.text((P(512), P(500)), "抖", font=font, fill=None,
           stroke_width=int(P(10)), stroke_fill=(72, 82, 106), anchor="mm")

    _rounded_arrow(d, P, P(512), P(230), P(730), P(150), PINK)
    _tray(d, P, P(512), P(800), P(210), P(52), CYAN)


def design_m1(d, s, bg=True):
    """M1 竖排极简：白色「抖」在上，粉色箭头居中在下，无托盘无描边"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(380)))
    d.text((P(512), P(430)), "抖", font=font, fill=WHITE, anchor="mm")

    _rounded_arrow(d, P, P(512), P(604), P(880), P(150), PINK)


def design_m2(d, s, bg=True):
    """M2 左右极简：白色「抖」在左，粉色箭头在右，两者垂直居中"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(420)))
    d.text((P(96), P(636)), "抖", font=font, fill=WHITE, anchor="ls")

    _rounded_arrow(d, P, P(768), P(300), P(724), P(136), PINK)


def design_m3(d, s, bg=True):
    """M3 箭头主导：粉色箭头 + 青色托盘，白色「抖」小字标贴在托盘下方"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    _rounded_arrow(d, P, P(512), P(180), P(660), P(180), PINK)
    _tray(d, P, P(512), P(712), P(236), P(54), CYAN)

    font = ImageFont.truetype(FONT_PATH, int(P(210)))
    d.text((P(512), P(872)), "抖", font=font, fill=WHITE, anchor="mm")


def design_m4(d, s, bg=True):
    """M4 单色融合：「抖」与箭头同色，仅靠笔画粗细区分，最克制"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=NAVY)

    font = ImageFont.truetype(FONT_PATH, int(P(430)))
    d.text((P(92), P(640)), "抖", font=font, fill=PINK, anchor="ls")
    _rounded_arrow(d, P, P(782), P(360), P(700), P(118), PINK)


def design_g(d, s, bg=True):
    """G 定稿：玫红底 + 白色大箭头 + 右上角青色点缀 + 底部「DY视频备份」"""
    from PIL import ImageFont

    def P(v):
        return v * s

    if bg:
        rr(d, [0, 0, P(1024), P(1024)], P(0), fill=PINK)

    # 白色大箭头（主体）
    _rounded_arrow(d, P, P(512), P(130), P(690), P(196), WHITE)

    # 右上角青色点缀（部分探出画布，形成圆角缺口感）
    d.ellipse([P(880), P(-120), P(1140), P(140)], fill=CYAN)

    # 底部小字
    font = ImageFont.truetype(FONT_PATH, int(P(122)))
    d.text((P(512), P(866)), "DY视频备份", font=font, fill=WHITE, anchor="mm")


DESIGNS = {"A": design_a, "B": design_b, "C": design_c, "D": design_d,
           "E1": design_e1, "E2": design_e2, "E3": design_e3,
           "F1": design_f1, "F2": design_f2, "F3": design_f3, "F4": design_f4,
           "M1": design_m1, "M2": design_m2, "M3": design_m3, "M4": design_m4,
           "G": design_g}

# 自适应图标背景色：D 用黑底，其余白底
ADAPTIVE_BG = {"A": "#FFFFFF", "B": "#FFFFFF", "C": "#FFFFFF", "D": "#0F0F0F",
               "G": "#F63E5C"}


def render(design, size, rounded=True, bg=True):
    img, d, s = canvas(size)
    DESIGNS[design](d, s, bg=bg)
    img = img.resize((size, size), Image.LANCZOS)

    if rounded:
        # Android 启动图标：圆角方形遮罩（自适应图标由系统裁切，这里给普通图用）
        mask = Image.new("L", (size * SS, size * SS), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle(
            [0, 0, size * SS, size * SS], radius=int(size * SS * 0.20), fill=255
        )
        mask = mask.resize((size, size), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        return out
    return img


RES = os.path.normpath(os.path.join(OUT, "..", "..", "android", "app", "src", "main", "res"))

MIPMAP = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def render_foreground(design, size):
    """自适应图标前景层：108dp 画布，内容缩放到中央安全区（约 66/108）。"""
    img, d, s = canvas(size)
    DESIGNS[design](d, s, bg=False)
    content = img.resize((size, size), Image.LANCZOS)
    # 内容按 61% 缩放并居中（安全区 66/108 ≈ 0.61，再留一点边）
    inner = int(size * 0.56)
    scaled = content.resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(scaled, ((size - inner) // 2, (size - inner) // 2), scaled)
    return out


def export(design):
    # 1) 各密度传统启动图标（带 20% 圆角，透明四角）
    for dens, size in MIPMAP.items():
        folder = os.path.join(RES, f"mipmap-{dens}")
        os.makedirs(folder, exist_ok=True)
        render(design, size, rounded=True).save(
            os.path.join(folder, "ic_launcher.png"))
        print(f"mipmap-{dens}/ic_launcher.png ({size}px)")

    # 2) 自适应图标前景层（背景用纯白 color resource）
    for dens, size in ADAPTIVE.items():
        folder = os.path.join(RES, f"mipmap-{dens}")
        render_foreground(design, size).save(
            os.path.join(folder, "ic_launcher_foreground.png"))
        print(f"mipmap-{dens}/ic_launcher_foreground.png ({size}px)")

    # 3) 自适应图标声明
    v26 = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(v26, exist_ok=True)
    with open(os.path.join(v26, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
    print("mipmap-anydpi-v26/ic_launcher.xml")

    values = os.path.join(RES, "values")
    with open(os.path.join(values, "ic_launcher_colors.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            f'    <color name="ic_launcher_background">{ADAPTIVE_BG[design]}</color>\n'
            '</resources>\n')
    print("values/ic_launcher_colors.xml")

    # 4) 启动页居中图标（mipmap-launch_image.png，各密度）
    for dens, size in MIPMAP.items():
        folder = os.path.join(RES, f"mipmap-{dens}")
        # 启动页用完整图标（含底色 + 圆角），居中缩放 72%
        icon = render(design, size, rounded=True)
        inner = int(size * 0.72)
        scaled = icon.resize((inner, inner), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(scaled, ((size - inner) // 2, (size - inner) // 2), scaled)
        out.save(os.path.join(folder, "launch_image.png"))
        print(f"mipmap-{dens}/launch_image.png ({size}px)")

    launch_bg = os.path.join(RES, "drawable", "launch_background.xml")
    with open(launch_bg, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <item android:drawable="@android:color/white"/>\n'
            '    <item>\n'
            '        <bitmap\n'
            '            android:gravity="center"\n'
            '            android:src="@mipmap/launch_image"/>\n'
            '    </item>\n'
            '</layer-list>\n')
    print("drawable/launch_background.xml")


def main():
    # 先出 512 大图供预览与挑选
    for name in DESIGNS:
        big = render(name, 512, rounded=True)
        big.save(os.path.join(OUT, f"preview_{name}.png"))
        print(f"生成 preview_{name}.png")

    # 三个方案拼成一张对比图
    pad = 32
    sheet = Image.new("RGB", (512 * 3 + pad * 4, 512 + pad * 2), (248, 249, 251))
    for i, name in enumerate(DESIGNS):
        ic = render(name, 512, rounded=True)
        sheet.paste(ic, (pad + i * (512 + pad), pad), ic)
    sheet.save(os.path.join(OUT, "compare.png"))
    print("生成 compare.png")

    # 定稿导出（可用命令行参数切换方案：python gen_icon.py export B）
    import sys
    choice = sys.argv[1] if len(sys.argv) > 1 else "A"
    if choice == "preview-m":
        names = ["M1", "M2", "M3", "M4"]
        pad = 28
        sheet = Image.new(
            "RGB", (512 * 4 + pad * 5, 512 + pad * 2), (248, 249, 251))
        for i, name in enumerate(names):
            ic = render(name, 512, rounded=True)
            ic.save(os.path.join(OUT, f"preview_{name}.png"))
            sheet.paste(ic, (pad + i * (512 + pad), pad), ic)
        sheet.save(os.path.join(OUT, "compare_m.png"))

        small_names = [48, 96, 192]
        sh = Image.new(
            "RGB",
            (512 * 4 + pad * 5, 192 * 3 + pad * 4),
            (248, 249, 251),
        )
        for row, size in enumerate(small_names):
            for i, name in enumerate(names):
                ic = render(name, size, rounded=True)
                x = pad + i * (512 + pad) + (512 - size) // 2
                y = pad + row * (192 + pad)
                sh.paste(ic, (x, y), ic)
        sh.save(os.path.join(OUT, "compare_m_small.png"))
        print("生成 compare_m.png / compare_m_small.png")
        return
    if choice == "preview-f":
        names = ["F1", "F2", "F3", "F4"]
        pad = 28
        sheet = Image.new(
            "RGB", (512 * 4 + pad * 5, 512 + pad * 2), (248, 249, 251))
        for i, name in enumerate(names):
            ic = render(name, 512, rounded=True)
            ic.save(os.path.join(OUT, f"preview_{name}.png"))
            sheet.paste(ic, (pad + i * (512 + pad), pad), ic)
        sheet.save(os.path.join(OUT, "compare_f.png"))

        small_names = [48, 96, 192]
        sh = Image.new(
            "RGB",
            (512 * 4 + pad * 5, 192 * 3 + pad * 4),
            (248, 249, 251),
        )
        for row, size in enumerate(small_names):
            for i, name in enumerate(names):
                ic = render(name, size, rounded=True)
                x = pad + i * (512 + pad) + (512 - size) // 2
                y = pad + row * (192 + pad)
                sh.paste(ic, (x, y), ic)
        sh.save(os.path.join(OUT, "compare_f_small.png"))
        print("生成 compare_f.png / compare_f_small.png")
        return
    if choice == "preview-e":
        # 方案 E 系列对比图：512 大图 + 小尺寸组合
        names = ["E1", "E2", "E3"]
        pad = 32
        sheet = Image.new(
            "RGB", (512 * 3 + pad * 4, 512 + pad * 2), (248, 249, 251))
        for i, name in enumerate(names):
            ic = render(name, 512, rounded=True)
            ic.save(os.path.join(OUT, f"preview_{name}.png"))
            sheet.paste(ic, (pad + i * (512 + pad), pad), ic)
        sheet.save(os.path.join(OUT, "compare_e.png"))

        # 小尺寸对比：48 / 96 / 192
        small_names = [48, 96, 192]
        sh = Image.new(
            "RGB",
            (512 * 3 + pad * 4, 192 * 3 + pad * 4),
            (248, 249, 251),
        )
        for row, size in enumerate(small_names):
            for i, name in enumerate(names):
                ic = render(name, size, rounded=True)
                x = pad + i * (512 + pad) + (512 - size) // 2
                y = pad + row * (192 + pad)
                sh.paste(ic, (x, y), ic)
        sh.save(os.path.join(OUT, "compare_e_small.png"))
        print("生成 compare_e.png / compare_e_small.png")
        return
    if choice == "export":
        choice = sys.argv[2] if len(sys.argv) > 2 else "A"
    if choice != "export":
        print(f"导出方案 {choice} 到工程 res/ ...")
        export(choice.upper())
        print("完成。")


if __name__ == "__main__":
    main()
