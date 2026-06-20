module NPC (
  input clock,
  input reset
);
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
  import "DPI-C" function void npc_trap(input int code, input int pc);

  reg [31:0] pc;
  reg [31:0] gpr [0:15];

  wire [31:0] inst = reset ? 32'h00000013 : pmem_read(pc);
  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [6:0] funct7 = inst[31:25];
  wire [3:0] rd  = inst[10:7];
  wire [3:0] rs1 = inst[18:15];
  wire [3:0] rs2 = inst[23:20];

  wire [31:0] src1 = gpr[rs1];
  wire [31:0] src2 = gpr[rs2];
  wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
  wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  wire [31:0] imm_u = {inst[31:12], 12'b0};

  wire is_add  = opcode == 7'b0110011 && funct3 == 3'b000 && funct7 == 7'b0000000;
  wire is_addi = opcode == 7'b0010011 && funct3 == 3'b000;
  wire is_lui  = opcode == 7'b0110111;
  wire is_lw   = opcode == 7'b0000011 && funct3 == 3'b010;
  wire is_lbu  = opcode == 7'b0000011 && funct3 == 3'b100;
  wire is_sw   = opcode == 7'b0100011 && funct3 == 3'b010;
  wire is_sb   = opcode == 7'b0100011 && funct3 == 3'b000;
  wire is_jalr = opcode == 7'b1100111 && funct3 == 3'b000;
  wire is_ebreak = inst == 32'h00100073;
  wire is_valid = is_add | is_addi | is_lui | is_lw | is_lbu | is_sw | is_sb | is_jalr | is_ebreak;

  wire [31:0] load_addr = src1 + imm_i;
  wire [31:0] store_addr = src1 + imm_s;
  wire [31:0] load_word = (is_lw | is_lbu) ? pmem_read(load_addr) : 32'b0;
  wire [7:0] load_byte =
    load_addr[1:0] == 2'b00 ? load_word[7:0] :
    load_addr[1:0] == 2'b01 ? load_word[15:8] :
    load_addr[1:0] == 2'b10 ? load_word[23:16] : load_word[31:24];

  integer i;

  always @(posedge clock) begin
    if (reset) begin
      pc <= 32'h80000000;
      for (i = 0; i < 16; i = i + 1) begin
        gpr[i] <= 32'b0;
      end
    end else begin
      if (is_ebreak) begin
        npc_trap(gpr[10], pc);
      end else begin
        if (is_add && rd != 0) begin
          gpr[rd] <= src1 + src2;
        end else if (is_addi && rd != 0) begin
          gpr[rd] <= src1 + imm_i;
        end else if (is_lui && rd != 0) begin
          gpr[rd] <= imm_u;
        end else if (is_lw && rd != 0) begin
          gpr[rd] <= load_word;
        end else if (is_lbu && rd != 0) begin
          gpr[rd] <= {24'b0, load_byte};
        end else if (is_sw) begin
          pmem_write(store_addr, src2, 8'h0f);
        end else if (is_sb) begin
          pmem_write(store_addr, src2 << {store_addr[1:0], 3'b000}, 8'h01 << store_addr[1:0]);
        end else if (is_jalr && rd != 0) begin
          gpr[rd] <= pc + 4;
        end else if (!is_valid) begin
          npc_trap(32'hffff_ffff, pc);
        end

        pc <= is_jalr ? ((src1 + imm_i) & 32'hffff_fffe) : pc + 4;
        gpr[0] <= 32'b0;
      end
    end
  end
endmodule
