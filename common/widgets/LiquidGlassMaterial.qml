import QtQuick
import ".."
import "../functions"

// Semantic reinterpretation of the local Kitty liquid-glass reference shader.
// Structure mirrors that material: a broad top reflection stronger than the
// left reflection, narrow reflected-light bands along each reflecting edge,
// an extra boost where the two reflections meet, and opposite-edge shadow
// falloff (bottom deeper than right). All tint derives from Noctalia
// on-layer/shadow roles; Hyprland remains responsible for blur.
Item {
    id: root

    property real radius: Appearance.rounding.normal
    property real strength: 1.0
    property bool active: false
    property color highlightColor: Appearance.colors.colOnLayer2
    property color shadowColor: Appearance.colors.colShadow
    // Relative lighting energy follows the reference ratios: top about 2.3x
    // left, bottom about 1.8x right, each specular band about 1.5x stronger
    // than its own broad edge ramp.
    property real topReflectionFactor: 0.56
    property real leftReflectionFactor: 0.24
    property real topSpecularFactor: 0.84
    property real leftSpecularFactor: 0.36
    property real bottomShadowFactor: 0.27
    property real rightShadowFactor: 0.15
    // Extra light where the top and left reflections meet.
    property real cornerHighlightFactor: 0.34
    readonly property real specularBandWidth: 4
    readonly property real shine: Config.options.overview.effects.glassShineOpacity

    visible: Config.options.overview.effects.glassMode
    clip: true

    // Smooth hover/active transitions so every surface shares one material feel.
    Behavior on strength {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: topReflection
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(34, Math.max(12, parent.height * 0.12))
        color: ColorUtils.applyAlpha(root.highlightColor, 0)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(
                    root.highlightColor,
                    root.shine * root.topReflectionFactor * root.strength)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.highlightColor, 0)
            }
        }
    }

    Rectangle {
        id: leftReflection
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(26, Math.max(10, parent.width * 0.075))
        color: ColorUtils.applyAlpha(root.highlightColor, 0)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(
                    root.highlightColor,
                    root.shine * root.leftReflectionFactor * root.strength)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.highlightColor, 0)
            }
        }
    }

    Rectangle {
        id: bottomFalloff
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(28, Math.max(11, parent.height * 0.105))
        color: ColorUtils.applyAlpha(root.shadowColor, 0)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(root.shadowColor, 0)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(
                    root.shadowColor,
                    root.shine * root.bottomShadowFactor * root.strength)
            }
        }
    }

    Rectangle {
        id: rightFalloff
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(22, Math.max(9, parent.width * 0.06))
        color: ColorUtils.applyAlpha(root.shadowColor, 0)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(root.shadowColor, 0)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(
                    root.shadowColor,
                    root.shine * root.rightShadowFactor * root.strength)
            }
        }
    }

    // Where the top and left reflections meet the reference adds extra light.
    Rectangle {
        id: cornerHighlight
        anchors.left: parent.left
        anchors.top: parent.top
        width: Math.min(topReflection.height, leftReflection.width)
        height: Math.min(topReflection.height, leftReflection.width)
        color: ColorUtils.applyAlpha(root.highlightColor, 0)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(
                    root.highlightColor,
                    root.shine * root.cornerHighlightFactor * root.strength)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.highlightColor, 0)
            }
        }
    }

    Rectangle {
        id: topSpecular
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.specularBandWidth
        color: ColorUtils.applyAlpha(root.highlightColor, 0)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(
                    root.highlightColor,
                    root.shine * root.topSpecularFactor * root.strength)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.highlightColor, 0)
            }
        }
    }

    Rectangle {
        id: leftSpecular
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.specularBandWidth
        color: ColorUtils.applyAlpha(root.highlightColor, 0)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(
                    root.highlightColor,
                    root.shine * root.leftSpecularFactor * root.strength)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.highlightColor, 0)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0)
        border.width: root.active ? 2 : 1
        border.color: root.active
            ? ColorUtils.applyAlpha(
                Appearance.colors.colPrimary,
                Math.min(0.42, root.shine * 2.2 * root.strength))
            : ColorUtils.applyAlpha(
                Appearance.colors.colOutline,
                Config.options.overview.effects.glassBorderOpacity * 0.42)
    }
}
