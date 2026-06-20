/* verilator lint_off DECLFILENAME */
module ysyx_231220000_core #(
  parameter [31:0] RESET_PC = 32'h8000_0000,
  parameter [31:0] MARCHID = 32'h0dc8_2320
) (
  input         clock,
  input         reset,
  output        io_ifu_reqValid,
  output [31:0] io_ifu_addr,
  input         io_ifu_respValid,
  input  [31:0] io_ifu_rdata,
  output        io_lsu_reqValid,
  output [31:0] io_lsu_addr,
  output [1:0]  io_lsu_size,
  output        io_lsu_wen,
  output [31:0] io_lsu_wdata,
  output [3:0]  io_lsu_wmask,
  input         io_lsu_respValid,
  input  [31:0] io_lsu_rdata,
  output        trap_valid,
  output [31:0] trap_code,
  output [31:0] trap_pc
);
  localparam [1:0] S_FETCH = 2'd0;
  localparam [1:0] S_EXEC  = 2'd1;
  localparam [1:0] S_MEM   = 2'd2;
  localparam [1:0] S_HALT  = 2'd3;

  reg [1:0] state;
  reg [31:0] pc;
  reg [31:0] inst;
  reg [31:0] gpr [0:31];
  reg [63:0] mcycle;
  reg [31:0] mem_addr;
  reg [1:0]  mem_size;
  reg        mem_wen;
  reg [31:0] mem_wdata;
  reg [3:0]  mem_wmask;
  reg [4:0]  mem_rd;
  reg [2:0]  mem_funct3;

  reg        trap_valid_r;
  reg [31:0] trap_code_r;
  reg [31:0] trap_pc_r;

  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [6:0] funct7 = inst[31:25];
  wire [4:0] rd     = inst[11:7];
  wire [4:0] rs1    = inst[19:15];
  wire [4:0] rs2    = inst[24:20];

  wire [31:0] src1 = gpr[rs1];
  wire [31:0] src2 = gpr[rs2];
  wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
  wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  wire [31:0] imm_u = {inst[31:12], 12'b0};
  wire [11:0] csr_addr = inst[31:20];
  wire [31:0] load_addr = src1 + imm_i;
  wire [31:0] store_addr = src1 + imm_s;

  wire is_add    = opcode == 7'b0110011 && funct3 == 3'b000 && funct7 == 7'b0000000;
  wire is_addi   = opcode == 7'b0010011 && funct3 == 3'b000;
  wire is_lui    = opcode == 7'b0110111;
  wire is_lw     = opcode == 7'b0000011 && funct3 == 3'b010;
  wire is_lbu    = opcode == 7'b0000011 && funct3 == 3'b100;
  wire is_sw     = opcode == 7'b0100011 && funct3 == 3'b010;
  wire is_sb     = opcode == 7'b0100011 && funct3 == 3'b000;
  wire is_jalr   = opcode == 7'b1100111 && funct3 == 3'b000;
  wire is_csrrs  = opcode == 7'b1110011 && funct3 == 3'b010;
  wire is_ebreak = inst == 32'h0010_0073;

  wire [31:0] csr_rdata =
    csr_addr == 12'hb00 ? mcycle[31:0] :
    csr_addr == 12'hb80 ? mcycle[63:32] :
    csr_addr == 12'hf11 ? 32'h7973_7978 :
    csr_addr == 12'hf12 ? MARCHID :
    32'b0;
  wire csr_valid = is_csrrs && (
    csr_addr == 12'hb00 || csr_addr == 12'hb80 ||
    csr_addr == 12'hf11 || csr_addr == 12'hf12
  );

  wire [31:0] load_data =
    mem_funct3 == 3'b010 ? io_lsu_rdata :
    mem_addr[1:0] == 2'b00 ? {24'b0, io_lsu_rdata[7:0]} :
    mem_addr[1:0] == 2'b01 ? {24'b0, io_lsu_rdata[15:8]} :
    mem_addr[1:0] == 2'b10 ? {24'b0, io_lsu_rdata[23:16]} :
                             {24'b0, io_lsu_rdata[31:24]};

  assign io_ifu_reqValid = (state == S_FETCH);
  assign io_ifu_addr = pc;
  assign io_lsu_reqValid = (state == S_MEM);
  assign io_lsu_addr = mem_addr;
  assign io_lsu_size = mem_size;
  assign io_lsu_wen = mem_wen;
  assign io_lsu_wdata = mem_wdata;
  assign io_lsu_wmask = mem_wmask;
  assign trap_valid = trap_valid_r;
  assign trap_code = trap_code_r;
  assign trap_pc = trap_pc_r;

  integer i;
  always @(posedge clock) begin
    if (reset) begin
      state <= S_FETCH;
      pc <= RESET_PC;
      inst <= 32'h0000_0013;
      mcycle <= 64'b0;
      mem_addr <= 32'b0;
      mem_size <= 2'b10;
      mem_wen <= 1'b0;
      mem_wdata <= 32'b0;
      mem_wmask <= 4'b0;
      mem_rd <= 5'b0;
      mem_funct3 <= 3'b0;
      trap_valid_r <= 1'b0;
      trap_code_r <= 32'b0;
      trap_pc_r <= 32'b0;
      for (i = 0; i < 32; i = i + 1) begin
        gpr[i] <= 32'b0;
      end
    end else begin
      mcycle <= mcycle + 64'd1;
      trap_valid_r <= 1'b0;
      case (state)
        S_FETCH: begin
          if (io_ifu_respValid) begin
            inst <= io_ifu_rdata;
            state <= S_EXEC;
          end
        end
        S_EXEC: begin
          if (is_ebreak) begin
            trap_valid_r <= 1'b1;
            trap_code_r <= gpr[10];
            trap_pc_r <= pc;
            state <= S_HALT;
          end else if (is_add) begin
            if (rd != 0) gpr[rd] <= src1 + src2;
            pc <= pc + 32'd4;
            state <= S_FETCH;
          end else if (is_addi) begin
            if (rd != 0) gpr[rd] <= src1 + imm_i;
            pc <= pc + 32'd4;
            state <= S_FETCH;
          end else if (is_lui) begin
            if (rd != 0) gpr[rd] <= imm_u;
            pc <= pc + 32'd4;
            state <= S_FETCH;
          end else if (is_jalr) begin
            if (rd != 0) gpr[rd] <= pc + 32'd4;
            pc <= (src1 + imm_i) & 32'hffff_fffe;
            state <= S_FETCH;
          end else if (csr_valid) begin
            if (rd != 0) gpr[rd] <= csr_rdata;
            pc <= pc + 32'd4;
            state <= S_FETCH;
          end else if (is_lw || is_lbu) begin
            mem_addr <= load_addr;
            mem_size <= is_lw ? 2'b10 : 2'b00;
            mem_wen <= 1'b0;
            mem_wdata <= 32'b0;
            mem_wmask <= 4'b0;
            mem_rd <= rd;
            mem_funct3 <= funct3;
            state <= S_MEM;
          end else if (is_sw || is_sb) begin
            mem_addr <= store_addr;
            mem_size <= is_sw ? 2'b10 : 2'b00;
            mem_wen <= 1'b1;
            mem_wdata <= is_sw ? src2 : (src2 << {store_addr[1:0], 3'b000});
            mem_wmask <= is_sw ? 4'hf : (4'b0001 << store_addr[1:0]);
            mem_rd <= 5'b0;
            mem_funct3 <= funct3;
            state <= S_MEM;
          end else begin
            trap_valid_r <= 1'b1;
            trap_code_r <= 32'hffff_ffff;
            trap_pc_r <= pc;
            state <= S_HALT;
          end
          gpr[0] <= 32'b0;
        end
        S_MEM: begin
          if (io_lsu_respValid) begin
            if (!mem_wen && mem_rd != 0) begin
              gpr[mem_rd] <= load_data;
            end
            pc <= pc + 32'd4;
            state <= S_FETCH;
            gpr[0] <= 32'b0;
          end
        end
        default: begin
          state <= S_HALT;
        end
      endcase
    end
  end
endmodule

module ysyx_231220000 (
  input         clock,
  input         reset,
  output        io_ifu_reqValid,
  output [31:0] io_ifu_addr,
  input         io_ifu_respValid,
  input  [31:0] io_ifu_rdata,
  output        io_lsu_reqValid,
  output [31:0] io_lsu_addr,
  output [1:0]  io_lsu_size,
  output        io_lsu_wen,
  output [31:0] io_lsu_wdata,
  output [3:0]  io_lsu_wmask,
  input         io_lsu_respValid,
  input  [31:0] io_lsu_rdata
);
  import "DPI-C" function void npc_trap(input int code, input int pc);

  wire trap_valid;
  wire [31:0] trap_code;
  wire [31:0] trap_pc;

  ysyx_231220000_core #(
    .RESET_PC(32'h3000_0000),
    .MARCHID(32'h0dc8_2320)
  ) core (
    .clock(clock),
    .reset(reset),
    .io_ifu_reqValid(io_ifu_reqValid),
    .io_ifu_addr(io_ifu_addr),
    .io_ifu_respValid(io_ifu_respValid),
    .io_ifu_rdata(io_ifu_rdata),
    .io_lsu_reqValid(io_lsu_reqValid),
    .io_lsu_addr(io_lsu_addr),
    .io_lsu_size(io_lsu_size),
    .io_lsu_wen(io_lsu_wen),
    .io_lsu_wdata(io_lsu_wdata),
    .io_lsu_wmask(io_lsu_wmask),
    .io_lsu_respValid(io_lsu_respValid),
    .io_lsu_rdata(io_lsu_rdata),
    .trap_valid(trap_valid),
    .trap_code(trap_code),
    .trap_pc(trap_pc)
  );

  always @(posedge clock) begin
    if (!reset && trap_valid) begin
      npc_trap(trap_code, trap_pc);
    end
  end
endmodule

module NPC (
  input clock,
  input reset
);
  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);
  import "DPI-C" function void npc_trap(input int code, input int pc);

  wire core_ifu_req_valid;
  wire [31:0] core_ifu_addr;
  reg core_ifu_resp_valid;
  reg [31:0] core_ifu_rdata;

  wire core_lsu_req_valid;
  wire [31:0] core_lsu_addr;
  /* verilator lint_off UNUSEDSIGNAL */
  wire [1:0] core_lsu_size;
  /* verilator lint_on UNUSEDSIGNAL */
  wire core_lsu_wen;
  wire [31:0] core_lsu_wdata;
  wire [3:0] core_lsu_wmask;
  reg core_lsu_resp_valid;
  reg [31:0] core_lsu_rdata;

  wire trap_valid;
  wire [31:0] trap_code;
  wire [31:0] trap_pc;

  reg ifu_inflight;
  reg lsu_inflight;
  reg [31:0] ifu_rdata_q;
  reg [31:0] lsu_addr_q;
  reg [31:0] lsu_rdata_q;
  reg lsu_wen_q;
  reg [31:0] lsu_wdata_q;
  reg [3:0] lsu_wmask_q;

  ysyx_231220000_core core (
    .clock(clock),
    .reset(reset),
    .io_ifu_reqValid(core_ifu_req_valid),
    .io_ifu_addr(core_ifu_addr),
    .io_ifu_respValid(core_ifu_resp_valid),
    .io_ifu_rdata(core_ifu_rdata),
    .io_lsu_reqValid(core_lsu_req_valid),
    .io_lsu_addr(core_lsu_addr),
    .io_lsu_size(core_lsu_size),
    .io_lsu_wen(core_lsu_wen),
    .io_lsu_wdata(core_lsu_wdata),
    .io_lsu_wmask(core_lsu_wmask),
    .io_lsu_respValid(core_lsu_resp_valid),
    .io_lsu_rdata(core_lsu_rdata),
    .trap_valid(trap_valid),
    .trap_code(trap_code),
    .trap_pc(trap_pc)
  );

  always @(posedge clock) begin
    if (reset) begin
      core_ifu_resp_valid <= 1'b0;
      core_ifu_rdata <= 32'b0;
      core_lsu_resp_valid <= 1'b0;
      core_lsu_rdata <= 32'b0;
      ifu_inflight <= 1'b0;
      lsu_inflight <= 1'b0;
      ifu_rdata_q <= 32'b0;
      lsu_addr_q <= 32'b0;
      lsu_rdata_q <= 32'b0;
      lsu_wen_q <= 1'b0;
      lsu_wdata_q <= 32'b0;
      lsu_wmask_q <= 4'b0;
    end else begin
      core_ifu_resp_valid <= 1'b0;
      if (ifu_inflight) begin
        core_ifu_resp_valid <= 1'b1;
        core_ifu_rdata <= ifu_rdata_q;
        ifu_inflight <= 1'b0;
      end else if (core_ifu_req_valid) begin
        ifu_inflight <= 1'b1;
        ifu_rdata_q <= pmem_read(core_ifu_addr);
      end

      core_lsu_resp_valid <= 1'b0;
      if (lsu_inflight) begin
        core_lsu_resp_valid <= 1'b1;
        if (lsu_wen_q) begin
          pmem_write(lsu_addr_q, lsu_wdata_q, {4'b0, lsu_wmask_q});
          core_lsu_rdata <= 32'b0;
        end else begin
          core_lsu_rdata <= lsu_rdata_q;
        end
        lsu_inflight <= 1'b0;
      end else if (core_lsu_req_valid) begin
        lsu_inflight <= 1'b1;
        lsu_addr_q <= core_lsu_addr;
        lsu_wen_q <= core_lsu_wen;
        lsu_wdata_q <= core_lsu_wdata;
        lsu_wmask_q <= core_lsu_wmask;
        if (!core_lsu_wen) begin
          lsu_rdata_q <= pmem_read(core_lsu_addr);
        end
      end

      if (trap_valid) begin
        npc_trap(trap_code, trap_pc);
      end
    end
  end
endmodule
/* verilator lint_on DECLFILENAME */
