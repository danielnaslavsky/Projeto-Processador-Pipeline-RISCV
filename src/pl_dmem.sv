`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [7:0]  addr,
    input  logic [31:0] WriteData,
    output logic [31:0] ReadData,
    input  logic [4:0]  LoadControl // Mantido para compatibilidade com a instância no datapath
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255]; [cite: 443]

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000; [cite: 443]
        $readmemh("data.hex", ram); 
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (MemWrite) ram[addr] <= WriteData; 
    end

    // Deixa a palavra completa sair. 
    // O bloco "always_comb" no pl_datapath.sv encarrega-se de extrair o Byte/Halfword.
    assign ReadData = ram[addr]; 

endmodule