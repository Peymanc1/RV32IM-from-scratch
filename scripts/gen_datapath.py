#!/usr/bin/env python3
# docs/datapath.svg : detailed module-connectivity datapath of rv32im_core_pipelined.sv
P=[]
def add(s): P.append(s)
def esc(t): return t.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
def txt(x,y,t,size=12,anchor="middle",weight="normal",fill="#1a1a1a",style=""):
    add(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" font-weight="{weight}" fill="{fill}" {style}>{esc(t)}</text>')
COLORS={"#15387a":"d","#c62828":"c","#6a1b9a":"f","#ef6c00":"h","#2e7d32":"g","#e65100":"e"}
def wire(pts,color="#15387a",sw=2.1,head=True,dash=None):
    d=f' stroke-dasharray="{dash}"' if dash else ''
    m=f' marker-end="url(#ar_{COLORS[color]})"' if head else ''
    add(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{sw}"{d}{m}/>')
def conn(p1,p2,midx,color="#15387a",sw=2.1,dash=None):
    x1,y1=p1; x2,y2=p2
    wire(f"{x1},{y1} {midx},{y1} {midx},{y2} {x2},{y2}",color,sw,True,dash)
def dot(x,y,c="#15387a"): add(f'<circle cx="{x}" cy="{y}" r="3.6" fill="{c}"/>')
def muxv(x,y,h,w=24):
    add(f'<polygon points="{x},{y} {x+w},{y+13} {x+w},{y+h-13} {x},{y+h}" fill="#dfe6ea" stroke="#455a64" stroke-width="1.8"/>')
    return {'cx':x+w/2,'top':(x,y+16),'mid':(x,y+h/2),'bot':(x,y+h-16),'out':(x+w,y+h/2),'sel':(x+w/2,y+h)}
def modp(x,y,w,role,inst,ins,outs,fill,stroke,dashed=False,minh=78):
    n=max(len(ins),len(outs)); h=max(minh, 52+n*16+12)
    da=' stroke-dasharray="7 5"' if dashed else ''
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="2.4"{da}/>')
    txt(x+w/2,y+22,role,15,"middle","bold","#10243f")
    txt(x+w/2,y+39,inst,10,"middle","normal","#6a7785",'font-style="italic"')
    ports={}; py=y+58
    for i,nm in enumerate(ins):
        yy=py+i*16; txt(x+7,yy+3,nm,9,"start","normal","#1d4e2a"); ports[nm]=(x,yy)
        add(f'<circle cx="{x}" cy="{yy}" r="2.6" fill="{stroke}"/>')
    for i,nm in enumerate(outs):
        yy=py+i*16; txt(x+w-7,yy+3,nm,9,"end","normal","#8a3b12"); ports[nm]=(x+w,yy)
        add(f'<circle cx="{x+w}" cy="{yy}" r="2.6" fill="{stroke}"/>')
    return ports,h

W,H=2640,1660
add(f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system, Segoe UI, Roboto, sans-serif">')
add('<defs>')
for c,i in COLORS.items():
    add(f'<marker id="ar_{i}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{c}"/></marker>')
add('</defs>')
add(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')

BY,BH=250,1060
bands=[("IF","#e7f1fb","#1565c0",30,400),("ID","#e9f7ec","#2e7d32",462,468),
       ("EX","#fff4e5","#e65100",962,820),("MEM","#f5ecf8","#6a1b9a",1814,348),
       ("WB","#e4f6f9","#00838f",2194,420)]
for name,fill,fg,x,w in bands:
    add(f'<rect x="{x}" y="{BY}" width="{w}" height="{BH}" fill="{fill}"/>')
    txt(x+w/2,238,name,23,"middle","bold",fg)
for nm,bx in [("IF / ID",436),("ID / EX",936),("EX / MEM",1788),("MEM / WB",2168)]:
    add(f'<rect x="{bx}" y="{BY}" width="22" height="{BH}" rx="3" fill="#37474f"/>')
    add(f'<text x="{bx+11}" y="760" text-anchor="middle" font-size="13" font-weight="bold" fill="#fff" transform="rotate(-90 {bx+11} 760)">{nm}</text>')

txt(30,42,"RV32IM 5-stage core — detailed datapath (rv32im_core_pipelined.sv)",18,"start","bold","#10243f")
txt(30,64,"each box = one .sv module with its real ports;  arrows = RTL signals;  green=PC/branch  purple=forwarding  orange=hazard  navy=data",12.5,"start","normal","#555")

# ================= modules =================
imem_p,_=modp(60,300,280,"Instruction Memory","external (I-cache)",["ADDR = imem_addr_o"],["RD = imem_data_i"],"#f4f4f4","#888",dashed=True)
pc_p,_  =modp(90,560,250,"Program Counter","u_pc · pc.sv",["stall_i","pc_sel_i","branch_target_i"],["pc_o","pc_plus4_o"],"#fff","#1565c0")

dec_p,_ =modp(500,300,322,"Decoder","u_decoder · decoder.sv",["inst_i [31:0]"],["opcode_o","rd_o","rs1_o","rs2_o","funct3_o","funct7_o"],"#fff","#2e7d32")
ctl_p,ch=modp(500,540,322,"Control Unit","u_ctrl · control_unit.sv",["opcode_i","funct3_i","funct7_i"],
      ["reg_we_o","alu_a_sel_o","alu_b_sel_o","alu_op_o","imm_type_o","mem_we_o","mem_re_o","wb_sel_o","br_type_o","is_b/jal/jalr/mdiv_o"],"#fff","#2e7d32")
imm_p,_ =modp(500,540+ch+24,322,"Immediate Gen","u_immgen · immgen.sv",["inst_i [31:0]","imm_type_i"],["imm_o [31:0]"],"#fff","#2e7d32")
rf_p,_  =modp(500,1010,322,"Register File","u_regfile · regfile.sv",["rs1_addr_i","rs2_addr_i","we_i","rd_addr_i","rd_data_i [31:0]"],["rs1_data_o [31:0]","rs2_data_o [31:0]"],"#fff","#2e7d32")

# EX muxes
fa=muxv(990,560,84); fb=muxv(990,820,84)
aa=muxv(1150,560,76); ab=muxv(1150,672,76)
alu_p,_=modp(1300,540,270,"ALU","u_alu · alu.sv",["operand_a_i [31:0]","operand_b_i [31:0]","alu_op_i"],["result_o [31:0]","zero_o"],"#ffe0b2","#e65100")
br_p,_ =modp(1300,760,270,"Branch Comparator","u_branch · branch_unit.sv",["rs1_i [31:0]","rs2_i [31:0]","br_type_i"],["taken_o"],"#fff","#e65100")
md_p,_ =modp(1300,920,270,"Mul / Div (M-ext)","u_mul_div · mul_div.sv",["start_i","funct3_i","operand_a_i","operand_b_i"],["result_o [31:0]","busy_o","done_o"],"#fff","#e65100")
rm=muxv(1620,580,84)

dm_p,_ =modp(1850,560,300,"Data Memory","external (D-cache / MMIO)",["ADDR = dmem_addr_o","DATAW = wdata","WE / RE","FUNC3"],["DATAR = dmem_rdata_i"],"#f4f4f4","#888",dashed=True)
wm=muxv(1850,860,90)

wb_p,_ =modp(2250,640,310,"Write-back","wb_rd / wb_rd_data / wb_reg_we",["memwb_rd_data [31:0]"],["-> regfile write"],"#fff","#00838f")

haz_p,_=modp(500,1350,400,"Hazard Unit","u_hazard · hazard_unit.sv",["id_rs1_i","id_rs2_i","ex_rd_i","ex_mem_re_i","mdiv_busy_i","mdiv_done_i"],
      ["stall_pc_o","stall_ifid_o","stall_idex_o","bubble_idex_o","bubble_exmem_o"],"#fde8e0","#ef6c00")
fwd_p,_=modp(1020,1350,440,"Forwarding Unit","u_fwd · forwarding_unit.sv",["ex_rs1_i","ex_rs2_i","mem_rd_i","mem_reg_we_i","wb_rd_i","wb_reg_we_i"],["fwd_a_o","fwd_b_o"],"#f3e5f5","#6a1b9a")

# mux labels
def muxlbl(m,sel,i0,i1,i2=None):
    txt(m['cx'],m['sel'][1]+13,sel,9,"middle","normal","#455a64")
    txt(m['top'][0]+4,m['top'][1]+3,i0,8,"start","normal","#455a64")
    txt(m['mid'][0]+4,m['mid'][1]+3,i1,8,"start","normal","#455a64")
    if i2: txt(m['bot'][0]+4,m['bot'][1]+3,i2,8,"start","normal","#455a64")
muxlbl(fa,"fwd_a","rf","M","W"); muxlbl(fb,"fwd_b","rf","M","W")
muxlbl(aa,"alu_a_sel","rs1","pc"); muxlbl(ab,"alu_b_sel","rs2","imm")
muxlbl(rm,"is_mdiv","alu","mdiv"); muxlbl(wm,"wb_sel","alu","mem")

# ================= wiring =================
# IF
conn(pc_p['pc_o'],imem_p['ADDR = imem_addr_o'],380); 
conn(imem_p['RD = imem_data_i'],(436,400),350); txt(348,470,"if_inst",9,"middle")
conn(pc_p['pc_plus4_o'],(436,360),360); txt(400,352,"pc_plus4 -> IF/ID",8.5,"middle")
# IF/ID -> ID
conn((458,360),dec_p['inst_i [31:0]'],474); txt(466,330,"ifid_inst[31:0]",9,"start")
conn((458,540),imm_p['inst_i [31:0]'],470)
# decoder -> control, regfile, ID/EX
conn(dec_p['opcode_o'],ctl_p['opcode_i'],470)
conn(dec_p['funct3_o'],ctl_p['funct3_i'],462)
conn(dec_p['funct7_o'],ctl_p['funct7_i'],466)
conn(dec_p['rs1_o'],rf_p['rs1_addr_i'],842); txt(846,1054,"rs1[19:15]",8.5,"start","normal","#2e7d32")
conn(dec_p['rs2_o'],rf_p['rs2_addr_i'],852)
# control -> immgen + bundle to ID/EX
conn(ctl_p['imm_type_o'],imm_p['imm_type_i'],858)
add(f'<rect x="836" y="560" width="92" height="220" rx="4" fill="none" stroke="#2e7d32" stroke-dasharray="4 3"/>')
txt(882,548,"control bundle -> ID/EX",8.5,"middle","normal","#2e7d32")
for nm in ["reg_we_o","alu_a_sel_o","alu_b_sel_o","alu_op_o","mem_we_o","mem_re_o","wb_sel_o","br_type_o","is_b/jal/jalr/mdiv_o"]:
    p=ctl_p[nm]; wire(f"{p[0]},{p[1]} 838,{p[1]}",color="#2e7d32",sw=1.5)
wire("928,650 936,650",color="#2e7d32")
# immgen + regfile -> ID/EX
conn(imm_p['imm_o [31:0]'],(936,imm_p['imm_o [31:0]'][1]),900); 
conn(rf_p['rs1_data_o [31:0]'],(936,1042),890); txt(900,1036,"rs1_data[31:0]",8.5,"start")
conn(rf_p['rs2_data_o [31:0]'],(936,1062),886); txt(900,1080,"rs2_data[31:0]",8.5,"start")
# ID/EX -> EX forwarding muxes
conn((958,1042),fa['top'],972); txt(960,600,"idex_rs1_data[31:0]",8.5,"start")
conn((958,1062),fb['top'],966); txt(960,860,"idex_rs2_data[31:0]",8.5,"start")
# fwd mux out -> alu operand muxes (rails)
conn(fa['out'],aa['top'],1080); txt(1040,594,"ex_rs1_fwd",8.5,"start")
dot(1080,fa['out'][1]); add(f'<line x1="1080" y1="{fa["out"][1]}" x2="1080" y2="1000" stroke="#15387a" stroke-width="2.1"/>')
conn(fb['out'],ab['top'],1110); txt(1040,854,"ex_rs2_fwd",8.5,"start")
dot(1110,fb['out'][1]); add(f'<line x1="1110" y1="{fb["out"][1]}" x2="1110" y2="1010" stroke="#15387a" stroke-width="2.1"/>')
# idex_pc -> alu_a_sel mux ; idex_imm -> alu_b_sel mux
conn((958,520),aa['mid'],1130,sw=2.0); txt(960,514,"idex_pc",8.5,"start","normal","#2e7d32")
conn((958,700),ab['mid'],1126); txt(960,716,"idex_imm",8.5,"start")
# alu operand muxes -> ALU
conn(aa['out'],alu_p['operand_a_i [31:0]'],1255)
conn(ab['out'],alu_p['operand_b_i [31:0]'],1250)
# rails -> branch + muldiv
conn((1080,790),br_p['rs1_i [31:0]'],1255); conn((1110,880),br_p['rs2_i [31:0]'],1240)
conn((1080,960),md_p['operand_a_i'],1255); conn((1110,980),md_p['operand_b_i'],1240)
# ALU/muldiv -> result mux
conn(alu_p['result_o [31:0]'],rm['top'],1600); txt(1576,560,"ex_alu_result",8.5,"start")
conn(md_p['result_o [31:0]'],rm['mid'],1590); txt(1576,980,"ex_mdiv_result",8.5,"start")
# result mux -> EX/MEM
conn(rm['out'],(1788,640),1700); txt(1660,634,"ex_result_final[31:0]",8.5,"start")
# branch taken -> green feedback to PC
wire(f"{br_p['taken_o'][0]},{br_p['taken_o'][1]} 1650,{br_p['taken_o'][1]}",color="#e65100"); txt(1576,790,"ex_br_taken_raw",8.5,"start","normal","#e65100")
wire(f"1650,{br_p['taken_o'][1]} 1650,200 200,200 200,560",color="#2e7d32")
txt(900,194,"ex_branch_taken / ex_branch_target  ->  u_pc.pc_sel_i, branch_target_i   +   flush_ifid / flush_idex",11,"start","normal","#2e7d32")
# store data rail -> EX/MEM
wire("1110,1010 1110,1130 1788,1130",sw=2.0); txt(1180,1124,"exmem_rs2_data = dmem_wdata_o",8.5,"start")
# EX/MEM -> MEM
conn((1810,640),dm_p['ADDR = dmem_addr_o'],1832); txt(1700,634,"exmem_alu_result[31:0]",8.5,"start","normal","#15387a")
conn((1810,720),wm['top'],1835); txt(1700,714,"exmem_alu_result",8.5,"start")
conn(dm_p['DATAR = dmem_rdata_i'],wm['mid'],2170); txt(2100,650,"dmem_rdata_i[31:0]",8.5,"end")
# wb_sel mux -> MEM/WB
conn(wm['out'],(2168,905),1980); txt(1900,900,"mem_wb_data[31:0]",8.5,"start")
txt(1830,1010,"mem_stall = exmem_valid & (mem_re|mem_we) & !dmem_ready_i",9,"start","normal","#6a1b9a")
# MEM/WB -> WB
conn((2190,905),wb_p['memwb_rd_data [31:0]'],2220); txt(2150,900,"memwb_rd_data",8.5,"start")
# WB -> regfile write (navy bottom rail) + bypass + fwd
wire(f"{wb_p['-> regfile write'][0]},{wb_p['-> regfile write'][1]} 2600,{wb_p['-> regfile write'][1]} 2600,1560 660,1560 660,1035",color="#15387a")
txt(1300,1554,"wb_rd_data / wb_rd / wb_reg_we  ->  Register File write port (we_i, rd_addr_i, rd_data_i)  +  WB->ID bypass  +  Forwarding Unit",11,"middle","normal","#15387a")
conn((660,1300),rf_p['rd_data_i [31:0]'],640,sw=1.8)
conn((640,1300),rf_p['we_i'],620,sw=1.8)
# forwarding selects -> fwd muxes (purple)
conn(fwd_p['fwd_a_o'],fa['sel'],1200,color="#6a1b9a",dash="7 5")
conn(fwd_p['fwd_b_o'],fb['sel'],1240,color="#6a1b9a",dash="7 5")
# forwarding candidate data -> fwd muxes (purple), two channels
wire(f"{wm['out'][0]+0},905 1730,905 1730,1200 962,1200 962,{fa['bot'][1]} {fa['bot'][0]},{fa['bot'][1]}",color="#6a1b9a",dash="7 5"); txt(1200,1194,"mem_wb_data (FWD_FROM_M)",9,"start","normal","#6a1b9a")
wire(f"2560,{wb_p['-> regfile write'][1]} 2560,1240 950,1240 950,{fb['bot'][1]} {fb['bot'][0]},{fb['bot'][1]}",color="#6a1b9a",dash="7 5"); txt(1200,1234,"wb_rd_data (FWD_FROM_W)",9,"start","normal","#6a1b9a")
# hazard outputs (orange)
conn(haz_p['stall_pc_o'],pc_p['stall_i'],470,color="#ef6c00",dash="6 5")
wire(f"{haz_p['stall_ifid_o'][0]},{haz_p['stall_ifid_o'][1]} 447,{haz_p['stall_ifid_o'][1]} 447,250",color="#ef6c00",dash="6 5"); txt(420,1320,"stall_ifid/flush -> IF/ID",8.5,"middle","normal","#b35400")
wire(f"{haz_p['stall_idex_o'][0]},{haz_p['stall_idex_o'][1]} 947,{haz_p['stall_idex_o'][1]} 947,250",color="#ef6c00",dash="6 5"); txt(700,1305,"stall_idex/bubble -> ID/EX",8.5,"middle","normal","#b35400")
wire(f"{haz_p['bubble_exmem_o'][0]},{haz_p['bubble_exmem_o'][1]} 1799,{haz_p['bubble_exmem_o'][1]} 1799,250",color="#ef6c00",dash="6 5"); txt(1300,1290,"bubble_exmem -> EX/MEM",8.5,"middle","normal","#b35400")
# mdiv busy/done -> hazard
conn(md_p['busy_o'],haz_p['mdiv_busy_i'],540,color="#ef6c00",dash="6 5")

add('</svg>')
open('docs/datapath.svg','w',encoding='utf-8').write('<?xml version="1.0" encoding="UTF-8"?>\n'+''.join(P)+'\n')
