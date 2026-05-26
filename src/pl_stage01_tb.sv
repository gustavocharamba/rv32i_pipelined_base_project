// =============================================================================
// pl_stage01_tb.sv
// Testbench -- Etapa 01 RV32I
//
// Testa no caminho completo da CPU as instrucoes:
//   R-type : XOR, SLL, SRL, SRA, SLTU
//   I-type : ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI
//
// O programa e carregado diretamente em dut.datapath.imem.rom, sem depender de
// program.hex. Ao detectar o halt, o testbench compara os registradores finais
// com os valores esperados e imprime PASS/FAIL.
// =============================================================================

`timescale 1ns / 1ps

module pl_stage01_tb;

    localparam CLK_PERIOD   = 100;
    localparam CLK_HALF     = CLK_PERIOD / 2;
    localparam RESET_CYCLES = 4;
    localparam MAX_CYCLES   = 2000;

    localparam OPCODE_OP     = 7'b0110011;
    localparam OPCODE_OP_IMM = 7'b0010011;
    localparam OPCODE_LOAD   = 7'b0000011;

    localparam NOP  = 32'h00000013; // addi x0,x0,0
    localparam HALT = 32'h00000063; // beq  x0,x0,0

    logic        clk;
    logic        rst_n;
    logic [31:0] PC;
    logic [17:0] SW = 18'b0;
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
    integer i;

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

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        enc_r = {funct7, rs2, rs1, funct3, rd, OPCODE_OP};
    endfunction

    function automatic logic [31:0] enc_i(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        enc_i = {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_shift_i(
        input logic [6:0] funct7,
        input logic [4:0] shamt,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        enc_shift_i = {funct7, shamt, rs1, funct3, rd, OPCODE_OP_IMM};
    endfunction

    task automatic load_stage01_program;
        begin
            for (i = 0; i < 256; i++) begin
                dut.datapath.imem.rom[i] = NOP;
                dut.datapath.dmem.ram[i] = 32'b0;
            end

            for (i = 0; i < 32; i++)
                dut.datapath.regfile.rf[i] = 32'b0;

            dut.datapath.dmem.ram[0] = 32'd42;

            // I-type da Etapa 01
            dut.datapath.imem.rom[0]  = enc_i(12'hFF8, 5'd0, 3'b000, 5'd1,  OPCODE_OP_IMM); // addi x1,x0,-8
            dut.datapath.imem.rom[1]  = enc_i(12'h003, 5'd0, 3'b000, 5'd2,  OPCODE_OP_IMM); // addi x2,x0,3
            dut.datapath.imem.rom[2]  = enc_i(12'h00C, 5'd0, 3'b000, 5'd3,  OPCODE_OP_IMM); // addi x3,x0,12
            dut.datapath.imem.rom[3]  = enc_shift_i(7'b0000000, 5'd2, 5'd2, 3'b001, 5'd4);   // slli x4,x2,2
            dut.datapath.imem.rom[4]  = enc_shift_i(7'b0000000, 5'd3, 5'd4, 3'b101, 5'd5);   // srli x5,x4,3
            dut.datapath.imem.rom[5]  = enc_shift_i(7'b0100000, 5'd3, 5'd1, 3'b101, 5'd6);   // srai x6,x1,3
            dut.datapath.imem.rom[6]  = enc_i(12'h00F, 5'd0, 3'b110, 5'd7,  OPCODE_OP_IMM); // ori  x7,x0,15
            dut.datapath.imem.rom[7]  = enc_i(12'h00A, 5'd7, 3'b111, 5'd8,  OPCODE_OP_IMM); // andi x8,x7,10
            dut.datapath.imem.rom[8]  = enc_i(12'h000, 5'd1, 3'b010, 5'd9,  OPCODE_OP_IMM); // slti x9,x1,0

            // R-type da Etapa 01
            dut.datapath.imem.rom[9]  = enc_r(7'b0000000, 5'd8,  5'd7,  3'b100, 5'd10); // xor  x10,x7,x8
            dut.datapath.imem.rom[10] = enc_r(7'b0000000, 5'd2,  5'd10, 3'b001, 5'd11); // sll  x11,x10,x2
            dut.datapath.imem.rom[11] = enc_r(7'b0000000, 5'd2,  5'd11, 3'b101, 5'd12); // srl  x12,x11,x2
            dut.datapath.imem.rom[12] = enc_r(7'b0100000, 5'd2,  5'd1,  3'b101, 5'd13); // sra  x13,x1,x2
            dut.datapath.imem.rom[13] = enc_r(7'b0000000, 5'd2,  5'd1,  3'b011, 5'd14); // sltu x14,x1,x2
            dut.datapath.imem.rom[14] = enc_r(7'b0000000, 5'd1,  5'd2,  3'b011, 5'd15); // sltu x15,x2,x1

            // Mais casos I-type e um load-use benigno para exercitar o pipeline.
            dut.datapath.imem.rom[15] = enc_i(12'h014, 5'd1,  3'b000, 5'd16, OPCODE_OP_IMM); // addi x16,x1,20
            dut.datapath.imem.rom[16] = enc_i(12'h010, 5'd8,  3'b110, 5'd17, OPCODE_OP_IMM); // ori  x17,x8,16
            dut.datapath.imem.rom[17] = enc_i(12'h01A, 5'd17, 3'b111, 5'd18, OPCODE_OP_IMM); // andi x18,x17,26
            dut.datapath.imem.rom[18] = enc_i(12'h000, 5'd0,  3'b010, 5'd19, OPCODE_LOAD);   // lw   x19,0(x0)
            dut.datapath.imem.rom[19] = enc_i(12'h013, 5'd2,  3'b000, 5'd20, OPCODE_OP_IMM); // addi x20,x2,19
            dut.datapath.imem.rom[20] = enc_i(12'h001, 5'd19, 3'b000, 5'd21, OPCODE_OP_IMM); // addi x21,x19,1
            dut.datapath.imem.rom[21] = HALT;
        end
    endtask

    task automatic expect_reg(
        input logic [4:0]  reg_num,
        input logic [31:0] expected,
        input string       label
    );
        logic [31:0] actual;
        begin
            actual = (reg_num == 5'd0) ? 32'b0 : dut.datapath.regfile.rf[reg_num];

            if (actual !== expected) begin
                errors++;
                $display("FAIL %-5s x%0d esperado=0x%08X obtido=0x%08X",
                         label, reg_num, expected, actual);
            end else begin
                $display("PASS %-5s x%0d = 0x%08X", label, reg_num, actual);
            end
        end
    endtask

    task automatic wait_for_halt;
        begin
            halt_cnt = 0;
            cycle_cnt = 0;

            for (i = 0; i <= 3; i++)
                pc_hist[i] = 32'hFFFFFFFF;

            while ((halt_cnt < 9) && (cycle_cnt < MAX_CYCLES)) begin
                @(posedge clk);
                #1;

                cycle_cnt++;
                pc_hist[3] = pc_hist[2];
                pc_hist[2] = pc_hist[1];
                pc_hist[1] = pc_hist[0];
                pc_hist[0] = PC;

                if ((pc_hist[0] != 32'hFFFFFFFF) &&
                    (pc_hist[3] != 32'hFFFFFFFF) &&
                    (pc_hist[0] == pc_hist[3]))
                    halt_cnt++;
                else
                    halt_cnt = 0;
            end

            if (cycle_cnt >= MAX_CYCLES) begin
                errors++;
                $display("FAIL halt nao detectado em %0d ciclos", MAX_CYCLES);
            end else begin
                $display("Halt detectado em PC=0x%08X apos %0d ciclos", PC, cycle_cnt);
            end
        end
    endtask

    task automatic check_results;
        begin
            expect_reg(5'd1,  32'hFFFFFFF8, "ADDI");
            expect_reg(5'd2,  32'h00000003, "ADDI");
            expect_reg(5'd3,  32'h0000000C, "ADDI");
            expect_reg(5'd4,  32'h0000000C, "SLLI");
            expect_reg(5'd5,  32'h00000001, "SRLI");
            expect_reg(5'd6,  32'hFFFFFFFF, "SRAI");
            expect_reg(5'd7,  32'h0000000F, "ORI");
            expect_reg(5'd8,  32'h0000000A, "ANDI");
            expect_reg(5'd9,  32'h00000001, "SLTI");
            expect_reg(5'd10, 32'h00000005, "XOR");
            expect_reg(5'd11, 32'h00000028, "SLL");
            expect_reg(5'd12, 32'h00000005, "SRL");
            expect_reg(5'd13, 32'hFFFFFFFF, "SRA");
            expect_reg(5'd14, 32'h00000000, "SLTU");
            expect_reg(5'd15, 32'h00000001, "SLTU");
            expect_reg(5'd16, 32'h0000000C, "ADDI");
            expect_reg(5'd17, 32'h0000001A, "ORI");
            expect_reg(5'd18, 32'h0000001A, "ANDI");
            expect_reg(5'd19, 32'h0000002A, "LW");
            expect_reg(5'd20, 32'h00000016, "ADDI");
            expect_reg(5'd21, 32'h0000002B, "ADDI");
        end
    endtask

    initial begin
        rst_n = 1'b0;
        errors = 0;

        #1;
        load_stage01_program();

        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait_for_halt();
        check_results();

        if (errors == 0)
            $display("PASS: Etapa 01 funcionando corretamente.");
        else
            $display("FAIL: Etapa 01 encontrou %0d erro(s).", errors);

        $finish;
    end

endmodule
