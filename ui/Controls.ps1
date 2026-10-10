# Native Button semantics, with readable disabled text instead of Windows' fixed gray.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('PanelThemeButton' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
public class PanelThemeButton : Button {
    public Color DisabledTextColor { get; set; }
    public Color DisabledBackColor { get; set; }
    public Color DisabledBorderColor { get; set; }
    protected override void OnPaint(PaintEventArgs e) {
        if (Enabled) { base.OnPaint(e); return; }
        var g = e.Graphics;
        g.Clear(DisabledBackColor.IsEmpty ? BackColor : DisabledBackColor);
        using (var pen = new Pen(DisabledBorderColor.IsEmpty ? FlatAppearance.BorderColor : DisabledBorderColor))
            g.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        var text = new Rectangle(Padding.Left, 0, Width - Padding.Horizontal, Height);
        if (Image != null) {
            using (var attributes = new ImageAttributes()) {
                var matrix = new ColorMatrix(); matrix.Matrix33 = 0.45f;
                attributes.SetColorMatrix(matrix);
                g.DrawImage(Image, new Rectangle(Padding.Left, (Height - Image.Height) / 2, Image.Width, Image.Height),
                    0, 0, Image.Width, Image.Height, GraphicsUnit.Pixel, attributes);
            }
            text.X += Image.Width + 6; text.Width -= Image.Width + 6;
        }
        TextRenderer.DrawText(g, Text, Font, text, DisabledTextColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
    }
}
'@
}
