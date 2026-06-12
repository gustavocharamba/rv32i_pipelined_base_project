// =============================================================================
// pl_dmem.sv
// Memoria de dados -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : data.mif   (sintese Quartus)
//              data.hex   (simulacao ModelSim via $readmemh)
//
// Leitura  : assincrona (combinatorial) -- disponivel no estagio MEM
// Escrita  : sincrona (posedge clk), com byte enable para SB/SH/SW
// Endereco : alu_result[9:2]  (endereco de palavra de 8 bits)
// =============================================================================

`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [3:0]  ByteEn,
    input  logic [7:0]  addr,
    input  logic [31:0] WriteData,
    output logic [31:0] ReadData
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000;
        $readmemh("data.hex", ram);
    end
    // synthesis translate_on

    always@(posedge clk) begin
        if (MemWrite) begin
            case (ByteEn)
                4'b0001: ram[addr] <= {ram[addr][31:8],  WriteData[7:0]};
                4'b0010: ram[addr] <= {ram[addr][31:16], WriteData[7:0],  ram[addr][7:0]};
                4'b0100: ram[addr] <= {ram[addr][31:24], WriteData[7:0],  ram[addr][15:0]};
                4'b1000: ram[addr] <= {WriteData[7:0],   ram[addr][23:0]};
                4'b0011: ram[addr] <= {ram[addr][31:16], WriteData[15:0]};
                4'b1100: ram[addr] <= {WriteData[15:0],  ram[addr][15:0]};
                default: ram[addr] <= WriteData;
            endcase
        end
    end

    assign ReadData = ram[addr];

endmodule
