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
    input logic [4:0] LoadControl,
    input logic [2:0] StoreControl // para controlar o tipo de store
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000;
        $readmemh("data.hex", ram);
    end
    // synthesis translate_on

    always@(posedge clk) begin
        if (MemWrite) begin   //STORE
            case (StoreControl)
            3'b000:  ram[addr] <= {ram[addr][31:8],WriteData[7:0]};  // SB
            3'b001: ram[addr] <= {ram[addr][31:16],WriteData[15:0]}; // SH
            3'b010: ram[addr] <= WriteData;                             // SW
            default: ram[addr] <= WriteData;    
            endcase

        end
    end

    always_comb begin 
        case(LoadControl)   //LOAD
        5'b00001: ReadData = {{24{ram[addr][7]}},ram[addr][7:0]};    // LB
        5'b00010: ReadData = {{16{ram[addr][15]}},ram[addr][15:0]};  // LH
        5'b00100: ReadData = ram[addr];                              // LW
        5'b01000: ReadData = {{24'b0},ram[addr][7:0]};               // LBU
        5'b10000:  ReadData = {{16'b0},ram[addr][15:0]};             // LHU
        default: ReadData = ram[addr];
    endcase
    end
        
endmodule
