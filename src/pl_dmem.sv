// =============================================================================
// pl_dmem.sv
// Memoria de dados -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : data.mif   (sintese Quartus)
//              data.hex   (simulacao ModelSim via $readmemh)
//
// Leitura  : assincrona (combinatorial) -- disponivel no estagio MEM
// Escrita  : sincrona (posedge clk, gated por MemWrite & ~mmio_sel)
// Endereco : alu_result[9:2]  (endereco de palavra de 8 bits)
// =============================================================================

`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [7:0]  addr,
    input  logic [31:0] WriteData,
    output logic [31:0] ReadData,
    input logic [4:0] LoadControl
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000;
        $readmemh("data.hex", ram);
    end
    // synthesis translate_on

    always@(posedge clk) begin
        if (MemWrite) ram[addr] <= WriteData;
    end

    assign ReadData = ram[addr];

    always_comb begin
        case(LoadControl)
        00001: ReadData = {{24{ram[addr][7]}},ram[addr][7:0]}; // LB
        00010: ReadData = {{16{ram[addr][15]}},ram[addr][15:0]};  // LH
        00100: ReadData = ram[addr];                            // LW
        01000: ReadData = {{24'b0},ram[addr][7:0]};             // LBU
        10000:  ReadData = {{16'b0},ram[addr][15:0]};            // LHU
        default: ReadData = ram[addr];
    endcase
    end
        
endmodule
