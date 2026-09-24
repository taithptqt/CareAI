# -*- coding: utf-8 -*-
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import parse_xml, OxmlElement
from docx.oxml.ns import nsdecls, qn

COLOR_PRIMARY = "1A365D"      # Deep Navy
COLOR_SECONDARY = "2B6CB0"    # Slate Blue
COLOR_ACCENT = "C53030"       # Deep Red / Alert
COLOR_AMBER = "D69E2E"        # Warning Amber
COLOR_TEXT_DARK = "2D3748"    # Slate Dark
COLOR_BG_LIGHT = "F7FAFC"     # Off-white / light slate
COLOR_BG_ALT = "EDF2F7"       # Table alternating row
COLOR_BORDER = "CBD5E0"       # Border grey

def create_styled_document():
    doc = docx.Document()
    
    # Page Margins: 1 inch on all sides
    for section in doc.sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)
        
        # Header / Footer
        header = section.header
        hp = header.paragraphs[0]
        hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        hrun = hp.add_run("CareAI System Specification · v111.0 Definitive Edition")
        hrun.font.name = "Calibri"
        hrun.font.size = Pt(8.5)
        hrun.font.color.rgb = RGBColor(160, 174, 192)
        
        footer = section.footer
        fp = footer.paragraphs[0]
        fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        frun = fp.add_run("Bản quyền © 2026 CareAI Project Team. Tuyệt mật & Lưu hành nội bộ.")
        frun.font.name = "Calibri"
        frun.font.size = Pt(8.5)
        frun.font.color.rgb = RGBColor(160, 174, 192)

    # Base Normal Style
    normal_style = doc.styles['Normal']
    normal_style.font.name = 'Calibri'
    normal_style.font.size = Pt(11)
    normal_style.font.color.rgb = RGBColor(45, 55, 72)
    normal_style.paragraph_format.line_spacing = 1.15
    normal_style.paragraph_format.space_after = Pt(4)
    normal_style.paragraph_format.space_before = Pt(0)
    
    return doc

def add_cover_page(doc, volume_num, volume_title, subtitle, roles_target, metadata_list):
    # Spacer
    for _ in range(2):
        doc.add_paragraph()
        
    p_badge = doc.add_paragraph()
    r_badge = p_badge.add_run(f"CAREAI ENTERPRISE TELEHEALTH ARCHITECTURE · TẬP {volume_num}")
    r_badge.font.name = "Calibri"
    r_badge.font.size = Pt(11)
    r_badge.font.bold = True
    r_badge.font.color.rgb = RGBColor(43, 108, 176)
    p_badge.paragraph_format.space_after = Pt(8)
    
    p_title = doc.add_paragraph()
    r_title = p_title.add_run(volume_title)
    r_title.font.name = "Calibri"
    r_title.font.size = Pt(24)
    r_title.font.bold = True
    r_title.font.color.rgb = RGBColor(26, 54, 93)
    p_title.paragraph_format.space_after = Pt(12)
    p_title.paragraph_format.line_spacing = 1.15
    
    p_sub = doc.add_paragraph()
    r_sub = p_sub.add_run(subtitle)
    r_sub.font.name = "Calibri"
    r_sub.font.size = Pt(13)
    r_sub.font.italic = True
    r_sub.font.color.rgb = RGBColor(74, 85, 104)
    p_sub.paragraph_format.space_after = Pt(24)
    
    # Decorative Divider Line
    p_div = doc.add_paragraph()
    p_div_border = parse_xml(f'<w:pBdr {nsdecls("w")}><w:bottom w:val="single" w:sz="18" w:space="1" w:color="{COLOR_PRIMARY}"/></w:pBdr>')
    p_div._p.get_or_add_pPr().append(p_div_border)
    p_div.paragraph_format.space_after = Pt(24)
    
    # Roles targeted callout
    p_role = doc.add_paragraph()
    r_role_lbl = p_role.add_run("VAI TRÒ TRỌNG TÂM TIẾP NHẬN: ")
    r_role_lbl.font.bold = True
    r_role_lbl.font.size = Pt(10.5)
    r_role_lbl.font.color.rgb = RGBColor(26, 54, 93)
    r_role_txt = p_role.add_run(roles_target)
    r_role_txt.font.size = Pt(10.5)
    p_role.paragraph_format.space_after = Pt(36)
    
    # Metadata Table
    table = doc.add_table(rows=len(metadata_list), cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    for i, (k, v) in enumerate(metadata_list):
        row = table.rows[i]
        c0, c1 = row.cells[0], row.cells[1]
        c0.width = Inches(2.2)
        c1.width = Inches(4.3)
        
        p0 = c0.paragraphs[0]
        r0 = p0.add_run(k)
        r0.font.bold = True
        r0.font.size = Pt(10)
        r0.font.color.rgb = RGBColor(74, 85, 104)
        p0.paragraph_format.space_after = Pt(2)
        
        p1 = c1.paragraphs[0]
        r1 = p1.add_run(v)
        r1.font.size = Pt(10)
        r1.font.color.rgb = RGBColor(26, 54, 93)
        p1.paragraph_format.space_after = Pt(2)
        
        # Bottom border on row
        shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{COLOR_BG_LIGHT if i % 2 == 0 else "FFFFFF"}"/>')
        c0._tc.get_or_add_tcPr().append(shd)
        shd2 = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{COLOR_BG_LIGHT if i % 2 == 0 else "FFFFFF"}"/>')
        c1._tc.get_or_add_tcPr().append(shd2)
    
    doc.add_page_break()

def add_heading_1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(16)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    
    # Bottom accent line
    p_border = parse_xml(f'<w:pBdr {nsdecls("w")}><w:bottom w:val="single" w:sz="12" w:space="4" w:color="{COLOR_PRIMARY}"/></w:pBdr>')
    p._p.get_or_add_pPr().append(p_border)
    
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(16)
    r.font.bold = True
    r.font.color.rgb = RGBColor(26, 54, 93)
    return p

def add_heading_2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(13)
    r.font.bold = True
    r.font.color.rgb = RGBColor(43, 108, 176)
    return p

def add_heading_3(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    
    r = p.add_run(text)
    r.font.name = "Calibri"
    r.font.size = Pt(11.5)
    r.font.bold = True
    r.font.color.rgb = RGBColor(45, 55, 72)
    return p

def add_paragraph(doc, text, bold_prefix=None, italic=False):
    p = doc.add_paragraph()
    if bold_prefix:
        r_bold = p.add_run(bold_prefix)
        r_bold.font.bold = True
        r_bold.font.color.rgb = RGBColor(26, 54, 93)
    r = p.add_run(text)
    if italic:
        r.font.italic = True
    return p

def add_bullet(doc, text, bold_prefix=None, level=0):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.left_indent = Inches(0.25 * (level + 1))
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(0)
    
    if bold_prefix:
        r_bold = p.add_run(bold_prefix)
        r_bold.font.bold = True
        r_bold.font.color.rgb = RGBColor(26, 54, 93)
    p.add_run(text)
    return p

def add_callout(doc, text, title="LƯU Ý QUAN TRỌNG", alert_type="note"):
    border_color = COLOR_SECONDARY
    bg_color = COLOR_BG_LIGHT
    if alert_type == "warning":
        border_color = COLOR_AMBER
    elif alert_type == "danger":
        border_color = COLOR_ACCENT
    elif alert_type == "success":
        border_color = "2F855A"

    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    cell = table.cell(0, 0)
    cell.width = Inches(6.5)
    
    # Left thick border & shading
    tcPr = cell._tc.get_or_add_tcPr()
    borders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="none"/>'
        f'<w:left w:val="single" w:sz="36" w:space="0" w:color="{border_color}"/>'
        f'<w:bottom w:val="none"/>'
        f'<w:right w:val="none"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(borders)
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{bg_color}"/>')
    tcPr.append(shd)
    
    # Internal margins
    tcMar = parse_xml(
        f'<w:tcMar {nsdecls("w")}>'
        f'<w:top w:w="120" w:type="dxa"/>'
        f'<w:bottom w:w="120" w:type="dxa"/>'
        f'<w:left w:w="200" w:type="dxa"/>'
        f'<w:right w:w="200" w:type="dxa"/>'
        f'</w:tcMar>'
    )
    tcPr.append(tcMar)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(2)
    r_title = p.add_run(f"[{title}] ")
    r_title.font.bold = True
    r_title.font.size = Pt(10)
    if alert_type == "warning":
        r_title.font.color.rgb = RGBColor(183, 121, 31)
    elif alert_type == "danger":
        r_title.font.color.rgb = RGBColor(197, 48, 48)
    else:
        r_title.font.color.rgb = RGBColor(43, 108, 176)
        
    r_text = p.add_run(text)
    r_text.font.size = Pt(10)
    r_text.font.color.rgb = RGBColor(45, 55, 72)
    
    # Space after table
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(0)
    sp.paragraph_format.space_after = Pt(4)

def add_styled_table(doc, headers, rows, col_widths=None):
    table = doc.add_table(rows=len(rows) + 1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    # Header Row
    hdr_cells = table.rows[0].cells
    for i, title in enumerate(headers):
        cell = hdr_cells[i]
        if col_widths and i < len(col_widths):
            cell.width = Inches(col_widths[i])
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        p.paragraph_format.space_before = Pt(4)
        p.paragraph_format.space_after = Pt(4)
        r = p.add_run(title)
        r.font.name = "Calibri"
        r.font.bold = True
        r.font.size = Pt(10)
        r.font.color.rgb = RGBColor(255, 255, 255)
        
        # Primary Color Background
        shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{COLOR_PRIMARY}"/>')
        cell._tc.get_or_add_tcPr().append(shd)
        
        # Cell margins
        tcMar = parse_xml(
            f'<w:tcMar {nsdecls("w")}>'
            f'<w:top w:w="80" w:type="dxa"/>'
            f'<w:bottom w:w="80" w:type="dxa"/>'
            f'<w:left w:w="120" w:type="dxa"/>'
            f'<w:right w:w="120" w:type="dxa"/>'
            f'</w:tcMar>'
        )
        cell._tc.get_or_add_tcPr().append(tcMar)
        
    # Data Rows
    for r_idx, row_data in enumerate(rows):
        row_cells = table.rows[r_idx + 1].cells
        bg_hex = COLOR_BG_LIGHT if r_idx % 2 == 0 else "FFFFFF"
        for c_idx, val in enumerate(row_data):
            cell = row_cells[c_idx]
            if col_widths and c_idx < len(col_widths):
                cell.width = Inches(col_widths[c_idx])
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(3)
            p.paragraph_format.space_after = Pt(3)
            r = p.add_run(str(val))
            r.font.name = "Calibri"
            r.font.size = Pt(9.5)
            r.font.color.rgb = RGBColor(45, 55, 72)
            
            # Row shading
            shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{bg_hex}"/>')
            cell._tc.get_or_add_tcPr().append(shd)
            
            # Cell border bottom
            tcPr = cell._tc.get_or_add_tcPr()
            borders = parse_xml(
                f'<w:tcBorders {nsdecls("w")}>'
                f'<w:top w:val="single" w:sz="4" w:space="0" w:color="{COLOR_BORDER}"/>'
                f'<w:left w:val="none"/>'
                f'<w:bottom w:val="single" w:sz="4" w:space="0" w:color="{COLOR_BORDER}"/>'
                f'<w:right w:val="none"/>'
                f'</w:tcBorders>'
            )
            tcPr.append(borders)
            
            # Cell margins
            tcMar = parse_xml(
                f'<w:tcMar {nsdecls("w")}>'
                f'<w:top w:w="70" w:type="dxa"/>'
                f'<w:bottom w:w="70" w:type="dxa"/>'
                f'<w:left w:w="120" w:type="dxa"/>'
                f'<w:right w:w="120" w:type="dxa"/>'
                f'</w:tcMar>'
            )
            tcPr.append(tcMar)
            
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(0)
    sp.paragraph_format.space_after = Pt(4)

def add_code_block(doc, code_text, lang=""):
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    cell = table.cell(0, 0)
    cell.width = Inches(6.5)
    
    tcPr = cell._tc.get_or_add_tcPr()
    borders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="single" w:sz="6" w:space="0" w:color="{COLOR_BORDER}"/>'
        f'<w:left w:val="single" w:sz="24" w:space="0" w:color="{COLOR_PRIMARY}"/>'
        f'<w:bottom w:val="single" w:sz="6" w:space="0" w:color="{COLOR_BORDER}"/>'
        f'<w:right w:val="single" w:sz="6" w:space="0" w:color="{COLOR_BORDER}"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(borders)
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="F8FAFC"/>')
    tcPr.append(shd)
    
    tcMar = parse_xml(
        f'<w:tcMar {nsdecls("w")}>'
        f'<w:top w:w="100" w:type="dxa"/>'
        f'<w:bottom w:w="100" w:type="dxa"/>'
        f'<w:left w:w="150" w:type="dxa"/>'
        f'<w:right w:w="150" w:type="dxa"/>'
        f'</w:tcMar>'
    )
    tcPr.append(tcMar)
    
    lines = code_text.splitlines()
    for i, line in enumerate(lines):
        if i == 0:
            p = cell.paragraphs[0]
        else:
            p = cell.add_paragraph()
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.05
        r = p.add_run(line)
        r.font.name = "Consolas"
        r.font.size = Pt(8.5)
        r.font.color.rgb = RGBColor(45, 55, 72)
        
    sp = doc.add_paragraph()
    sp.paragraph_format.space_before = Pt(0)
    sp.paragraph_format.space_after = Pt(4)
