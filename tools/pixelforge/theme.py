"""Emits the Godot Theme resource that skins every control in the game.

Generated rather than hand-written so the theme can never drift from the
palette the art was drawn with.
"""
from __future__ import annotations

from pathlib import Path

from . import palette as P

# Text sizes map onto the four font atlases (7/14/21/28 px cap heights).
FONT_SCALES = {"small": 1, "body": 2, "title": 3, "display": 4}
FONT_SIZES = {"small": 7, "body": 14, "title": 21, "display": 28}


def _color(c) -> str:
    return f"Color({c[0] / 255:.4f}, {c[1] / 255:.4f}, {c[2] / 255:.4f}, {c[3] / 255:.4f})"


class _Builder:
    def __init__(self) -> None:
        self.ext: list[str] = []
        self.sub: list[str] = []
        self.body: list[str] = []
        self._ext_ids: dict[str, str] = {}
        self._n = 0

    def texture(self, name: str) -> str:
        if name in self._ext_ids:
            return self._ext_ids[name]
        ident = f"tex_{name}"
        self.ext.append(
            f'[ext_resource type="Texture2D" '
            f'path="res://Assets/UI/{name}.png" id="{ident}"]'
        )
        self._ext_ids[name] = ident
        return ident

    def font(self, key: str) -> str:
        scale = FONT_SCALES[key]
        name = f"font_{key}"
        if name in self._ext_ids:
            return self._ext_ids[name]
        self.ext.append(
            f'[ext_resource type="FontFile" '
            f'path="res://Assets/Fonts/nightbane_{scale}x.fnt" id="{name}"]'
        )
        self._ext_ids[name] = name
        return name

    def stylebox_texture(
        self,
        ident: str,
        texture: str,
        *,
        margin: int = 5,
        content: tuple[int, int, int, int] = (10, 8, 10, 8),
        axis_h: int = 1,
        axis_v: int = 1,
    ) -> str:
        tex = self.texture(texture)
        self.sub.append(
            f'[sub_resource type="StyleBoxTexture" id="{ident}"]\n'
            f'texture = ExtResource("{tex}")\n'
            f"texture_margin_left = {margin}\ntexture_margin_top = {margin}\n"
            f"texture_margin_right = {margin}\ntexture_margin_bottom = {margin}\n"
            f"content_margin_left = {content[0]}\ncontent_margin_top = {content[1]}\n"
            f"content_margin_right = {content[2]}\ncontent_margin_bottom = {content[3]}\n"
            f"axis_stretch_horizontal = {axis_h}\naxis_stretch_vertical = {axis_v}\n"
        )
        return ident

    def stylebox_empty(self, ident: str, content=(0, 0, 0, 0)) -> str:
        self.sub.append(
            f'[sub_resource type="StyleBoxEmpty" id="{ident}"]\n'
            f"content_margin_left = {content[0]}\ncontent_margin_top = {content[1]}\n"
            f"content_margin_right = {content[2]}\ncontent_margin_bottom = {content[3]}\n"
        )
        return ident

    def stylebox_flat(self, ident: str, color, *, radius: int = 0, border: int = 0,
                      border_color=P.VOID, content=(0, 0, 0, 0)) -> str:
        lines = [
            f'[sub_resource type="StyleBoxFlat" id="{ident}"]',
            f"bg_color = {_color(color)}",
            f"corner_radius_top_left = {radius}",
            f"corner_radius_top_right = {radius}",
            f"corner_radius_bottom_right = {radius}",
            f"corner_radius_bottom_left = {radius}",
        ]
        if border:
            lines += [
                f"border_width_left = {border}", f"border_width_top = {border}",
                f"border_width_right = {border}", f"border_width_bottom = {border}",
                f"border_color = {_color(border_color)}",
            ]
        lines += [
            f"content_margin_left = {content[0]}", f"content_margin_top = {content[1]}",
            f"content_margin_right = {content[2]}", f"content_margin_bottom = {content[3]}",
        ]
        self.sub.append("\n".join(lines) + "\n")
        return ident

    def set(self, key: str, value: str) -> None:
        self.body.append(f"{key} = {value}")

    def render(self) -> str:
        steps = len(self.ext) + len(self.sub)
        head = f"[gd_resource type=\"Theme\" load_steps={steps + 1} format=3]\n"
        return (
            head
            + "\n"
            + "\n".join(self.ext)
            + "\n\n"
            + "\n".join(self.sub)
            + "\n[resource]\n"
            + "\n".join(self.body)
            + "\n"
        )


def build() -> str:
    b = _Builder()

    body_font = b.font("body")
    small_font = b.font("small")
    title_font = b.font("title")
    display_font = b.font("display")

    # -- shared styleboxes --------------------------------------------------
    b.stylebox_texture("sb_panel", "panel", content=(12, 12, 12, 12))
    b.stylebox_texture("sb_panel_dark", "panel_dark", content=(12, 12, 12, 12))
    b.stylebox_texture("sb_panel_inset", "panel_inset", content=(8, 6, 8, 6))
    b.stylebox_texture("sb_panel_ornate", "panel_ornate", content=(14, 14, 14, 14))
    b.stylebox_texture("sb_panel_blood", "panel_blood", content=(12, 12, 12, 12))
    b.stylebox_texture("sb_tooltip", "tooltip", content=(8, 6, 8, 6))
    for state in ("normal", "hover", "pressed", "disabled"):
        b.stylebox_texture(f"sb_btn_{state}", f"button_{state}", content=(18, 10, 18, 10))
    b.stylebox_texture("sb_btn_focus", "button_focus", content=(18, 10, 18, 10))
    b.stylebox_texture("sb_bar_bg", "bar_bg", margin=3, content=(0, 0, 0, 0))
    b.stylebox_texture("sb_bar_health", "bar_health", margin=3, content=(0, 0, 0, 0))
    b.stylebox_texture("sb_bar_xp", "bar_xp", margin=3, content=(0, 0, 0, 0))
    b.stylebox_texture("sb_scroll_bg", "scroll_bg", margin=3, content=(0, 0, 0, 0))
    b.stylebox_texture("sb_scroll_thumb", "scroll_thumb", margin=3, content=(0, 0, 0, 0))
    # Dedicated flats for HSlider — ProgressBar 9-slices are nearly invisible on
    # dark panels (only the grabber showed). High-contrast trough + crimson fill.
    b.stylebox_flat(
        "sb_slider",
        P.INK,
        radius=3,
        border=2,
        border_color=P.ASH,
        content=(4, 7, 4, 7),
    )
    b.stylebox_flat(
        "sb_slider_fill",
        P.CRIMSON,
        radius=3,
        border=1,
        border_color=P.EMBER,
        content=(4, 7, 4, 7),
    )
    b.stylebox_flat(
        "sb_slider_fill_hi",
        P.EMBER,
        radius=3,
        border=1,
        border_color=P.CANDLE,
        content=(4, 7, 4, 7),
    )
    b.stylebox_empty("sb_empty")
    b.stylebox_flat("sb_selected", P.mix(P.UI_PANEL_HI, P.BLOOD, 0.45), content=(4, 2, 4, 2))

    # -- defaults -----------------------------------------------------------
    b.set("default_font", f'ExtResource("{body_font}")')
    b.set("default_font_size", str(FONT_SIZES["body"]))

    # -- Label --------------------------------------------------------------
    b.set("Label/colors/font_color", _color(P.UI_TEXT))
    b.set("Label/colors/font_shadow_color", _color((0, 0, 0, 200)))
    b.set("Label/constants/shadow_offset_x", "2")
    b.set("Label/constants/shadow_offset_y", "2")
    b.set("Label/constants/shadow_outline_size", "0")
    b.set("Label/constants/line_spacing", "4")
    b.set("Label/font_sizes/font_size", str(FONT_SIZES["body"]))

    # Named label variations the scenes use for hierarchy.
    for name, (font_key, color) in {
        "TitleLabel": ("title", P.CRIMSON),
        "DisplayLabel": ("display", P.CRIMSON),
        "SubtitleLabel": ("body", P.UI_TEXT_DIM),
        "SmallLabel": ("small", P.UI_TEXT_DIM),
        "GoldLabel": ("body", P.AMBER),
        "StatLabel": ("small", P.UI_TEXT),
        "DangerLabel": ("body", P.EMBER),
        "SpectralLabel": ("body", P.SPECTRAL),
    }.items():
        f = b.font(font_key)
        b.set(f"{name}/base_type", '&"Label"')
        b.set(f"{name}/fonts/font", f'ExtResource("{f}")')
        b.set(f"{name}/font_sizes/font_size", str(FONT_SIZES[font_key]))
        b.set(f"{name}/colors/font_color", _color(color))
        b.set(f"{name}/colors/font_shadow_color", _color((0, 0, 0, 210)))
        b.set(f"{name}/constants/shadow_offset_x", "2")
        b.set(f"{name}/constants/shadow_offset_y", "2")
        b.set(f"{name}/constants/line_spacing", "4")

    # -- Button -------------------------------------------------------------
    b.set("Button/styles/normal", 'SubResource("sb_btn_normal")')
    b.set("Button/styles/hover", 'SubResource("sb_btn_hover")')
    b.set("Button/styles/pressed", 'SubResource("sb_btn_pressed")')
    b.set("Button/styles/disabled", 'SubResource("sb_btn_disabled")')
    b.set("Button/styles/focus", 'SubResource("sb_btn_focus")')
    b.set("Button/colors/font_color", _color(P.UI_TEXT))
    b.set("Button/colors/font_hover_color", _color(P.CANDLE))
    b.set("Button/colors/font_pressed_color", _color(P.ROSE))
    b.set("Button/colors/font_disabled_color", _color(P.UI_TEXT_DIM))
    b.set("Button/colors/font_focus_color", _color(P.CANDLE))
    b.set("Button/colors/font_outline_color", _color(P.VOID))
    b.set("Button/constants/outline_size", "0")
    b.set("Button/font_sizes/font_size", str(FONT_SIZES["body"]))
    b.set("Button/fonts/font", f'ExtResource("{body_font}")')

    # A quieter button for lists and back actions.
    b.set('FlatButton/base_type', '&"Button"')
    b.set("FlatButton/styles/normal", 'SubResource("sb_panel_dark")')
    b.set("FlatButton/styles/hover", 'SubResource("sb_btn_hover")')
    b.set("FlatButton/styles/pressed", 'SubResource("sb_btn_pressed")')
    b.set("FlatButton/styles/disabled", 'SubResource("sb_btn_disabled")')
    b.set("FlatButton/styles/focus", 'SubResource("sb_btn_focus")')
    b.set("FlatButton/colors/font_color", _color(P.UI_TEXT))
    b.set("FlatButton/colors/font_hover_color", _color(P.CANDLE))
    b.set("FlatButton/fonts/font", f'ExtResource("{body_font}")')
    b.set("FlatButton/font_sizes/font_size", str(FONT_SIZES["body"]))

    # -- Panels -------------------------------------------------------------
    b.set("Panel/styles/panel", 'SubResource("sb_panel")')
    b.set("PanelContainer/styles/panel", 'SubResource("sb_panel")')
    for name, style in (
        ("DarkPanel", "sb_panel_dark"),
        ("InsetPanel", "sb_panel_inset"),
        ("OrnatePanel", "sb_panel_ornate"),
        ("BloodPanel", "sb_panel_blood"),
    ):
        b.set(f"{name}/base_type", '&"PanelContainer"')
        b.set(f"{name}/styles/panel", f'SubResource("{style}")')

    # -- ProgressBar --------------------------------------------------------
    b.set("ProgressBar/styles/background", 'SubResource("sb_bar_bg")')
    b.set("ProgressBar/styles/fill", 'SubResource("sb_bar_health")')
    b.set("ProgressBar/colors/font_color", _color(P.UI_TEXT))
    b.set("ProgressBar/fonts/font", f'ExtResource("{small_font}")')
    b.set("ProgressBar/font_sizes/font_size", str(FONT_SIZES["small"]))
    b.set("XpBar/base_type", '&"ProgressBar"')
    b.set("XpBar/styles/background", 'SubResource("sb_bar_bg")')
    b.set("XpBar/styles/fill", 'SubResource("sb_bar_xp")')

    # -- Sliders / checkboxes ----------------------------------------------
    b.set("HSlider/styles/slider", 'SubResource("sb_slider")')
    b.set("HSlider/styles/grabber_area", 'SubResource("sb_slider_fill")')
    b.set("HSlider/styles/grabber_area_highlight", 'SubResource("sb_slider_fill_hi")')
    b.set("HSlider/icons/grabber", f'ExtResource("{b.texture("slider_grabber")}")')
    b.set("HSlider/icons/grabber_highlight", f'ExtResource("{b.texture("slider_grabber_hover")}")')
    b.set("HSlider/icons/grabber_disabled", f'ExtResource("{b.texture("slider_grabber")}")')
    b.set("HSlider/constants/center_grabber", "1")
    b.set("HSlider/constants/grabber_offset", "0")

    b.set("CheckBox/icons/unchecked", f'ExtResource("{b.texture("check_off")}")')
    b.set("CheckBox/icons/checked", f'ExtResource("{b.texture("check_on")}")')
    b.set("CheckBox/icons/radio_unchecked", f'ExtResource("{b.texture("radio_off")}")')
    b.set("CheckBox/icons/radio_checked", f'ExtResource("{b.texture("radio_on")}")')
    b.set("CheckBox/styles/normal", 'SubResource("sb_empty")')
    b.set("CheckBox/styles/hover", 'SubResource("sb_empty")')
    b.set("CheckBox/styles/pressed", 'SubResource("sb_empty")')
    b.set("CheckBox/styles/focus", 'SubResource("sb_empty")')
    b.set("CheckBox/colors/font_color", _color(P.UI_TEXT))
    b.set("CheckBox/colors/font_hover_color", _color(P.CANDLE))
    b.set("CheckBox/fonts/font", f'ExtResource("{body_font}")')
    b.set("CheckBox/font_sizes/font_size", str(FONT_SIZES["body"]))

    # -- Scrolling ----------------------------------------------------------
    b.set("VScrollBar/styles/scroll", 'SubResource("sb_scroll_bg")')
    b.set("VScrollBar/styles/grabber", 'SubResource("sb_scroll_thumb")')
    b.set("VScrollBar/styles/grabber_highlight", 'SubResource("sb_scroll_thumb")')
    b.set("VScrollBar/styles/grabber_pressed", 'SubResource("sb_scroll_thumb")')
    b.set("ScrollContainer/styles/panel", 'SubResource("sb_empty")')

    # -- Popups / tooltips --------------------------------------------------
    b.set("TooltipPanel/styles/panel", 'SubResource("sb_tooltip")')
    b.set("TooltipLabel/colors/font_color", _color(P.UI_TEXT))
    b.set("TooltipLabel/fonts/font", f'ExtResource("{small_font}")')
    b.set("TooltipLabel/font_sizes/font_size", str(FONT_SIZES["small"]))
    b.set("PopupMenu/styles/panel", 'SubResource("sb_panel")')
    b.set("PopupMenu/styles/hover", 'SubResource("sb_selected")')
    b.set("PopupMenu/colors/font_color", _color(P.UI_TEXT))
    b.set("PopupMenu/fonts/font", f'ExtResource("{body_font}")')
    b.set("PopupMenu/font_sizes/font_size", str(FONT_SIZES["body"]))

    b.set("OptionButton/styles/normal", 'SubResource("sb_btn_normal")')
    b.set("OptionButton/styles/hover", 'SubResource("sb_btn_hover")')
    b.set("OptionButton/styles/pressed", 'SubResource("sb_btn_pressed")')
    b.set("OptionButton/styles/focus", 'SubResource("sb_btn_focus")')
    b.set("OptionButton/colors/font_color", _color(P.UI_TEXT))
    b.set("OptionButton/fonts/font", f'ExtResource("{body_font}")')
    b.set("OptionButton/font_sizes/font_size", str(FONT_SIZES["body"]))

    # A flat 1px rule. A nine-sliced texture here inherits content margins and
    # inflates into a solid slab, which is what a separator must never be.
    b.stylebox_flat("sb_sep", P.UI_BORDER, content=(0, 0, 0, 0))
    b.set("HSeparator/styles/separator", 'SubResource("sb_sep")')
    b.set("HSeparator/constants/separation", "5")
    b.set("VSeparator/styles/separator", 'SubResource("sb_sep")')
    b.set("VSeparator/constants/separation", "5")

    # Unused-but-referenced fonts keep their ExtResource alive.
    b.set("DisplayLabel/fonts/font", f'ExtResource("{display_font}")')
    b.set("TitleLabel/fonts/font", f'ExtResource("{title_font}")')

    return b.render()


def export(root: Path) -> Path:
    path = root / "Assets" / "UI" / "nightbane_theme.tres"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(build())
    return path
