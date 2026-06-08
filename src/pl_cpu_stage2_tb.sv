// =============================================================================
// pl_cpu_stage2_tb.sv
// Testbench -- Etapa 2 RV32I pipelined
//
// Testa as instrucoes pedidas na Etapa 2:
//   Loads/stores menores : LB, LH, LBU, LHU, SB, SH
//   Branches            : BNE, BLT, BGE, BLTU, BGEU
//   Jumps               : JAL, JALR
//   U-type              : LUI, AUIPC
//
// O programa e carregado diretamente na imem/dmem do DUT para nao depender dos
// arquivos program.hex/data.hex usados por outros testes do projeto.
// =============================================================================

`timescale 1ns / 1ps

module pl_cpu_stage2_tb;

    localparam CLK_PERIOD   = 100;
    localparam CLK_HALF     = CLK_PERIOD / 2;
    localparam RESET_CYCLES = 4;
    localparam MAX_CYCLES   = 2000;

    localparam logic [31:0] NOP = 32'h00000013; // addi x0,x0,0

    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_IMM    = 7'b0010011;

    localparam logic [2:0] F3_ADDI = 3'b000;
    localparam logic [2:0] F3_LB   = 3'b000;
    localparam logic [2:0] F3_LH   = 3'b001;
    localparam logic [2:0] F3_LW   = 3'b010;
    localparam logic [2:0] F3_LBU  = 3'b100;
    localparam logic [2:0] F3_LHU  = 3'b101;
    localparam logic [2:0] F3_SB   = 3'b000;
    localparam logic [2:0] F3_SH   = 3'b001;
    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_BNE  = 3'b001;
    localparam logic [2:0] F3_BLT  = 3'b100;
    localparam logic [2:0] F3_BGE  = 3'b101;
    localparam logic [2:0] F3_BLTU = 3'b110;
    localparam logic [2:0] F3_BGEU = 3'b111;

    logic        clk, rst_n;
    logic [31:0] PC;
    logic [17:0] SW = 18'h0;
    logic [3:0]  KEY = 4'hF;
    logic [17:0] LEDR;
    logic [8:0]  LEDG;
    logic        UART_TXD;
    logic        UART_RXD = 1'b1;

    logic        wb_reg_write;
    logic [4:0]  wb_reg_dst;
    logic [31:0] wb_reg_data;
    logic        mem_wr_en;
    logic [7:0]  mem_wr_addr;
    logic [31:0] mem_wr_data;

    integer errors;
    integer cycle_cnt;
    integer halt_cnt;
    integer pcw;
    integer auipc_word;
    integer jal_word;
    integer jalr_word;
    integer jalr_target_word;

    logic [31:0] pc_hist [0:3];

    pl_cpu dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .PC           (PC),
        .SW           (SW),
        .KEY_IO       (KEY),
        .LEDR         (LEDR),
        .LEDG         (LEDG),
        .UART_TXD     (UART_TXD),
        .UART_RXD     (UART_RXD),
        .wb_reg_write (wb_reg_write),
        .wb_reg_dst   (wb_reg_dst),
        .wb_reg_data  (wb_reg_data),
        .mem_wr_en    (mem_wr_en),
        .mem_wr_addr  (mem_wr_addr),
        .mem_wr_data  (mem_wr_data)
    );

    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        #1;
        load_stage2_program();
        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    initial begin
        errors    = 0;
        cycle_cnt = 0;
        halt_cnt  = 0;
        pc_hist[0] = 32'hFFFFFFFF;
        pc_hist[1] = 32'hFFFFFFFF;
        pc_hist[2] = 32'hFFFFFFFF;
        pc_hist[3] = 32'hFFFFFFFF;

        @(posedge rst_n);

        while (halt_cnt < 9 && cycle_cnt < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycle_cnt++;

            pc_hist[3] = pc_hist[2];
            pc_hist[2] = pc_hist[1];
            pc_hist[1] = pc_hist[0];
            pc_hist[0] = PC;

            if (pc_hist[0] != 32'hFFFFFFFF &&
                pc_hist[3] != 32'hFFFFFFFF &&
                pc_hist[0] == pc_hist[3])
                halt_cnt++;
            else
                halt_cnt = 0;
        end

        if (cycle_cnt >= MAX_CYCLES) begin
            $display("FAIL: timeout apos %0d ciclos.", MAX_CYCLES);
            errors++;
        end else begin
            $display("Halt detectado em PC=0x%08X apos %0d ciclos.", PC, cycle_cnt);
        end

        check_stage2_results();

        if (errors == 0)
            $display("PASS: Etapa 2 funcionando.");
        else
            $display("FAIL: %0d erro(s) encontrado(s) na Etapa 2.", errors);

        $stop;
    end

    // -------------------------------------------------------------------------
    // Encoders RV32I usados pelo programa de teste
    // -------------------------------------------------------------------------
    function automatic logic [31:0] enc_i(
        input logic signed [31:0] imm,
        input logic [4:0]         rs1,
        input logic [2:0]         funct3,
        input logic [4:0]         rd,
        input logic [6:0]         opcode
    );
        enc_i = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(
        input logic signed [31:0] imm,
        input logic [4:0]         rs2,
        input logic [4:0]         rs1,
        input logic [2:0]         funct3
    );
        enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], OP_STORE};
    endfunction

    function automatic logic [31:0] enc_b(
        input logic signed [31:0] imm,
        input logic [4:0]         rs2,
        input logic [4:0]         rs1,
        input logic [2:0]         funct3
    );
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], OP_BRANCH};
    endfunction

    function automatic logic [31:0] enc_u(
        input logic [19:0] imm20,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        enc_u = {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_j(
        input logic signed [31:0] imm,
        input logic [4:0]         rd
    );
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, OP_JAL};
    endfunction

    task automatic emit(input logic [31:0] instr, input string asm_text);
        begin
            dut.datapath.imem.rom[pcw] = instr;
            $display("IMEM[%0d] = 0x%08X  // %s", pcw, instr, asm_text);
            pcw++;
        end
    endtask

    task automatic load_stage2_program();
        integer i;
        begin
            for (i = 0; i < 256; i++) begin
                dut.datapath.imem.rom[i] = NOP;
                dut.datapath.dmem.ram[i] = 32'h00000000;
            end

            for (i = 0; i < 32; i++)
                dut.datapath.regfile.rf[i] = 32'h00000000;

            // Palavra 0: bytes 01 7F FF 80, em little-endian.
            // Usada para testar extensao com sinal e extensao com zero.
            dut.datapath.dmem.ram[0] = 32'h80FF7F01;

            // Palavra 1 sera modificada por SB e SH.
            dut.datapath.dmem.ram[1] = 32'h11223344;

            pcw = 0;

            emit(enc_i(2,  5'd0, F3_LB,  5'd1, OP_LOAD), "lb   x1,2(x0)");
            emit(enc_i(2,  5'd0, F3_LH,  5'd2, OP_LOAD), "lh   x2,2(x0)");
            emit(enc_i(2,  5'd0, F3_LBU, 5'd3, OP_LOAD), "lbu  x3,2(x0)");
            emit(enc_i(2,  5'd0, F3_LHU, 5'd4, OP_LOAD), "lhu  x4,2(x0)");
            emit(enc_i(1,  5'd0, F3_LB,  5'd5, OP_LOAD), "lb   x5,1(x0)");

            emit(enc_i(170, 5'd0, F3_ADDI, 5'd6, OP_IMM), "addi x6,x0,170");
            emit(enc_s(5, 5'd6, 5'd0, F3_SB),              "sb   x6,5(x0)");
            emit(enc_u(20'h0000C, 5'd7, OP_LUI),           "lui  x7,0x0000C");
            emit(enc_i(-273, 5'd7, F3_ADDI, 5'd7, OP_IMM), "addi x7,x7,-273");
            emit(enc_s(6, 5'd7, 5'd0, F3_SH),              "sh   x7,6(x0)");
            emit(enc_i(4, 5'd0, F3_LW, 5'd8, OP_LOAD),     "lw   x8,4(x0)");

            emit(enc_i(1,  5'd0, F3_ADDI, 5'd9,  OP_IMM), "addi x9,x0,1");
            emit(enc_i(2,  5'd0, F3_ADDI, 5'd10, OP_IMM), "addi x10,x0,2");
            emit(enc_i(-1, 5'd0, F3_ADDI, 5'd11, OP_IMM), "addi x11,x0,-1");

            // Branches verdadeiros: devem pular o incremento de x31.
            emit(enc_b(8, 5'd10, 5'd9,  F3_BNE),  "bne  x9,x10,+8");
            emit(enc_i(1, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,1");
            emit(enc_b(8, 5'd9,  5'd11, F3_BLT),  "blt  x11,x9,+8");
            emit(enc_i(2, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,2");
            emit(enc_b(8, 5'd11, 5'd9,  F3_BGE),  "bge  x9,x11,+8");
            emit(enc_i(4, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,4");
            emit(enc_b(8, 5'd11, 5'd9,  F3_BLTU), "bltu x9,x11,+8");
            emit(enc_i(8, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,8");
            emit(enc_b(8, 5'd9,  5'd11, F3_BGEU), "bgeu x11,x9,+8");
            emit(enc_i(16, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,16");

            // Branches falsos: nao devem pular o incremento de x30.
            emit(enc_b(8, 5'd9,  5'd9,  F3_BNE),  "bne  x9,x9,+8");
            emit(enc_i(1, 5'd30, F3_ADDI, 5'd30, OP_IMM), "addi x30,x30,1");
            emit(enc_b(8, 5'd11, 5'd9,  F3_BLT),  "blt  x9,x11,+8");
            emit(enc_i(1, 5'd30, F3_ADDI, 5'd30, OP_IMM), "addi x30,x30,1");
            emit(enc_b(8, 5'd9,  5'd11, F3_BGE),  "bge  x11,x9,+8");
            emit(enc_i(1, 5'd30, F3_ADDI, 5'd30, OP_IMM), "addi x30,x30,1");
            emit(enc_b(8, 5'd9,  5'd11, F3_BLTU), "bltu x11,x9,+8");
            emit(enc_i(1, 5'd30, F3_ADDI, 5'd30, OP_IMM), "addi x30,x30,1");
            emit(enc_b(8, 5'd11, 5'd9,  F3_BGEU), "bgeu x9,x11,+8");
            emit(enc_i(1, 5'd30, F3_ADDI, 5'd30, OP_IMM), "addi x30,x30,1");

            emit(enc_u(20'h12345, 5'd20, OP_LUI), "lui   x20,0x12345");
            auipc_word = pcw;
            emit(enc_u(20'h00001, 5'd21, OP_AUIPC), "auipc x21,0x00001");

            jal_word = pcw;
            emit(enc_j(8, 5'd22), "jal  x22,+8");
            emit(enc_i(32, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,32");

            jalr_target_word = pcw + 3;
            emit(enc_i(jalr_target_word * 4, 5'd0, F3_ADDI, 5'd23, OP_IMM),
                 "addi x23,x0,jalr_target");
            jalr_word = pcw;
            emit(enc_i(0, 5'd23, F3_ADDI, 5'd24, OP_JALR), "jalr x24,x23,0");
            emit(enc_i(64, 5'd31, F3_ADDI, 5'd31, OP_IMM), "addi x31,x31,64");

            emit(enc_i(42, 5'd0, F3_ADDI, 5'd25, OP_IMM), "addi x25,x0,42");
            emit(enc_b(0, 5'd0, 5'd0, F3_BEQ), "beq  x0,x0,0");
        end
    endtask

    task automatic check_reg(
        input integer      idx,
        input logic [31:0] expected,
        input string       name
    );
        logic [31:0] got;
        begin
            got = dut.datapath.regfile.rf[idx];
            if (got !== expected) begin
                $display("ERRO %s: x%0d esperado=0x%08X obtido=0x%08X",
                         name, idx, expected, got);
                errors++;
            end else begin
                $display("OK   %s: x%0d = 0x%08X", name, idx, got);
            end
        end
    endtask

    task automatic check_mem(
        input integer      idx,
        input logic [31:0] expected,
        input string       name
    );
        logic [31:0] got;
        begin
            got = dut.datapath.dmem.ram[idx];
            if (got !== expected) begin
                $display("ERRO %s: dmem[%0d] esperado=0x%08X obtido=0x%08X",
                         name, idx, expected, got);
                errors++;
            end else begin
                $display("OK   %s: dmem[%0d] = 0x%08X", name, idx, got);
            end
        end
    endtask

    task automatic check_stage2_results();
        begin
            $display("--- Checando loads da Etapa 2 ---");
            check_reg(1, 32'hFFFFFFFF, "LB com sinal");
            check_reg(2, 32'hFFFF80FF, "LH com sinal");
            check_reg(3, 32'h000000FF, "LBU sem sinal");
            check_reg(4, 32'h000080FF, "LHU sem sinal");
            check_reg(5, 32'h0000007F, "LB positivo");

            $display("--- Checando stores da Etapa 2 ---");
            check_reg(8, 32'hBEEFAA44, "LW apos SB/SH");
            check_mem(1, 32'hBEEFAA44, "SB + SH");

            $display("--- Checando branches da Etapa 2 ---");
            check_reg(30, 32'h00000005, "branches falsos nao tomados");
            check_reg(31, 32'h00000000, "branches/jumps tomados pularam erros");

            $display("--- Checando jumps e U-type da Etapa 2 ---");
            check_reg(20, 32'h12345000, "LUI");
            check_reg(21, (auipc_word * 4) + 32'h00001000, "AUIPC");
            check_reg(22, (jal_word * 4) + 4, "JAL link PC+4");
            check_reg(24, (jalr_word * 4) + 4, "JALR link PC+4");
            check_reg(25, 32'h0000002A, "JALR alcancou alvo");
        end
    endtask

endmodule
