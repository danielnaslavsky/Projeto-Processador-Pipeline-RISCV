// =============================================================================
// pl_datapath.sv
// Datapath pipeline de 5 estagios -- RV32I (P&H secoes 4.6-4.10)
//
// Estagios:
//   IF  -- busca instrucao (pl_imem, PC)
//   ID  -- decodificacao, leitura de registradores, deteccao de hazard
//   EX  -- execucao (ALU), resolucao de branch, forwarding
//   MEM -- acesso a memoria de dados / MMIO
//   WB  -- escrita no banco de registradores
//
// Tratamento de hazards:
//   Load-use stall : 1 ciclo de bolha (pl_hazard)
//   RAW data       : forwarding EX/MEM -> EX e MEM/WB -> EX (pl_forward)
//   Branch taken   : flush de IF e ID (2 NOPs) na resolucao em EX
//
// Decodificacao de endereco (estagio MEM):
//   alu_result[10] = 0 -> memoria de dados  (0x000-0x3FF)
//   alu_result[10] = 1 -> MMIO              (0x400-0x7FF)
//     alu_result[4:2] seleciona periferico dentro da janela MMIO
// =============================================================================

`timescale 1ns / 1ps

import pl_pipe_pkg::*;

module pl_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Sinais de controle vindos do estagio ID (pl_control)
    input  logic        ALUSrc,
    input  logic        MemtoReg,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic [1:0]  ALUOp,
    input  logic        Jump, //implementado
    input  logic        Jalr, //implemetnado
    input logic Lui, //implementado
    input logic Auipc,//implementado

    // Codigo de operacao da ALU (pl_alu_ctrl, usa campos do estagio EX)
    input  logic [3:0]  ALU_CC,

    // Campos realimentados ao pl_cpu para controle e ALU ctrl
    output logic [6:0]  Opcode,       // opcode do estagio ID (para pl_control)
    output logic [2:0]  Funct3_EX,    // funct3 do estagio EX (para pl_alu_ctrl)
    output logic [6:0]  Funct7_EX,    // funct7 do estagio EX (para pl_alu_ctrl)
    output logic [1:0]  ALUOp_EX,     // ALUOp do estagio EX  (para pl_alu_ctrl)

    output logic [31:0] PC,           // PC atual (testbench / debug)

    // E/S Mapeada em Memoria -- DE2-115
    input  logic [17:0] SW,
    input  logic [3:0]  KEY,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    // Observabilidade para o testbench
    output logic        wb_reg_write,   // pulso quando WB escreve registrador
    output logic [4:0]  wb_reg_dst,     // registrador destino (WB)
    output logic [31:0] wb_reg_data,    // dado escrito (WB)
    output logic        mem_wr_en,      // escrita na dmem (nao MMIO)
    output logic [7:0]  mem_wr_addr,    // endereco de palavra da dmem (MEM)
    output logic [31:0] mem_wr_data     // dado escrito na dmem (MEM)
);

    // =========================================================================
    // Sinais internos
    // =========================================================================

    // PC
    logic [31:0] pc_reg, pc_plus4;

    // Registradores de pipeline
    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    // Hazard / branch
    logic        stall;
    logic        pc_src;
    logic [31:0] branch_target;

    // ID
    logic [31:0] rd1, rd2, imm_ext;

    // EX -- forwarding
    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] fwd_srca, fwd_srcb, alu_srcb;
    logic [31:0] alu_result;
    logic        zero;

    // WB
    logic [31:0] wb_data;

    // MEM
    logic        mmio_sel;
    logic [31:0] dmem_rd, mmio_rd, mem_read_data;
    logic [31:0] mem_read_data_formatted; // Dado extraído e estendido para LOAD
    logic [31:0] mem_write_data_formatted; // Dado modificado para STORE

    // =========================================================================
    // IF -- Busca de instrucao
    // =========================================================================
    logic [31:0] instr_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'b0;
        else if (pc_src) pc_reg <= branch_target;   // branch tem prioridade
        else if (!stall) pc_reg <= pc_plus4;
        // else stall: PC mantido
    end

    assign PC       = pc_reg;
    assign pc_plus4 = pc_reg + 32'd4;

    pl_imem imem (
        .addr  (pc_reg[9:2]),
        .instr (instr_if)
    );

    // =========================================================================
    // Registrador IF/ID
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                    // reset assicrono (unico sinal na lista)
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (pc_src) begin           // flush sincrono: branch taken
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (!stall) begin           // avanco normal
            if_id.pc    <= pc_reg;
            if_id.instr <= instr_if;
        end
        // else stall: mantido
    end

    // =========================================================================
    // ID -- Decodificacao, banco de registradores, imediato, hazard
    // =========================================================================
    assign Opcode = if_id.instr[6:0];

    // Deteccao de hazard load-use
    pl_hazard hazard (
        .if_id_rs1      (if_id.instr[19:15]),
        .if_id_rs2      (if_id.instr[24:20]),
        .id_ex_rd       (id_ex.rd),
        .id_ex_mem_read (id_ex.mem_read),
        .stall          (stall)
    );

    // Dado de write-back (mux WB): usado tambem pelo forwarding MEM/WB->EX
    assign wb_data = mem_wb.mem_to_reg ? mem_wb.read_data : mem_wb.alu_result;

    pl_regfile regfile (
        .clk       (clk),
        .RegWrite  (mem_wb.reg_write),
        .rs1       (if_id.instr[19:15]),
        .rs2       (if_id.instr[24:20]),
        .rd        (mem_wb.rd),
        .WriteData (wb_data),
        .ReadData1 (rd1),
        .ReadData2 (rd2)
    );

    pl_sign_ext sign_ext (
        .Instr  (if_id.instr),
        .ImmExt (imm_ext)
    );

    // Saidas para o testbench (estagio WB)
    assign wb_reg_write = mem_wb.reg_write;
    assign wb_reg_dst   = mem_wb.rd;
    assign wb_reg_data  = wb_data;

    // =========================================================================
    // Registrador ID/EX
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      // reset assicrono (unico sinal na lista)
            id_ex.alu_src    <= 1'b0;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
            id_ex.jump       <= 1'b0; //novo
            id_ex.jalr       <= 1'b0;
            id_ex.lui   <= 1'b0;
            id_ex.auipc <= 1'b0;
        end else if (stall || pc_src) begin    // NOP sincrono: load-use ou branch
            id_ex.alu_src    <= 1'b0;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
            id_ex.jump       <= 1'b0; //novo
            id_ex.jalr       <= 1'b0; //novo
            id_ex.lui   <= 1'b0; //novo
            id_ex.auipc <= 1'b0; //novo
        end else begin
            id_ex.alu_src    <= ALUSrc;
            id_ex.mem_to_reg <= MemtoReg;
            id_ex.reg_write  <= RegWrite;
            id_ex.mem_read   <= MemRead;
            id_ex.mem_write  <= MemWrite;
            id_ex.alu_op     <= ALUOp;
            id_ex.branch     <= Branch;
            id_ex.pc         <= if_id.pc;
            id_ex.rd1        <= rd1;
            id_ex.rd2        <= rd2;
            id_ex.rs1        <= if_id.instr[19:15];
            id_ex.rs2        <= if_id.instr[24:20];
            id_ex.rd         <= if_id.instr[11:7];
            id_ex.imm_ext    <= imm_ext;
            id_ex.funct3     <= if_id.instr[14:12];
            id_ex.funct7     <= if_id.instr[31:25];
            id_ex.jump       <= Jump; //Sinal do Jump do Control para para saber se redireciona o PC quando é JAL E JALR
            id_ex.jalr       <= Jalr; //Sinal do JALR para saber se o alvo do pulo vem do rs1 em vez do pc e precisa zerar o bit 0.
            id_ex.lui   <= Lui; //Sinal para LUI
            id_ex.auipc <= Auipc; // //Sinal para AUIPC
        end
    end

    // Realimentacao para pl_alu_ctrl (usa campos do estagio EX)
    assign Funct3_EX = id_ex.funct3;
    assign Funct7_EX = id_ex.funct7;
    assign ALUOp_EX  = id_ex.alu_op;

    // =========================================================================
    // EX -- Forwarding, ALU, resolucao de branch
    // =========================================================================
    pl_forward forward (
        .id_ex_rs1        (id_ex.rs1),
        .id_ex_rs2        (id_ex.rs2),
        .ex_mem_rd        (ex_mem.rd),
        .mem_wb_rd        (mem_wb.rd),
        .ex_mem_reg_write (ex_mem.reg_write),
        .mem_wb_reg_write (mem_wb.reg_write),
        .forward_a        (fwd_a),
        .forward_b        (fwd_b)
    );

    // Mux de forwarding para SrcA
    always_comb begin
        case (fwd_a)
            2'b10:   fwd_srca = ex_mem.alu_result;
            2'b01:   fwd_srca = wb_data;
            default: fwd_srca = id_ex.rd1;
        endcase
    end

    // Mux de forwarding para SrcB (antes do mux ALUSrc)
    always_comb begin
        case (fwd_b)
            2'b10:   fwd_srcb = ex_mem.alu_result;
            2'b01:   fwd_srcb = wb_data;
            default: fwd_srcb = id_ex.rd2;
        endcase
    end

    logic [31:0] alu_srca; //criamos sinal interno para 

    always_comb begin
        if (id_ex.lui)
            alu_srca = 32'b0;           //LUI = 0 + imm
        else if (id_ex.auipc)
            alu_srca = id_ex.pc;        //AUIPC = PC atual + imm
        else
            alu_srca = fwd_srca;        //normal
    end

    // Mux ALUSrc: imediato ou registrador
    assign alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb;
    
    //Lógica de resolução de Branches (Estágio EX)
    logic branch_taken;

    always_comb begin
        branch_taken = 1'b0; //Padrão: não salta
        
        if (id_ex.branch) begin
            case (id_ex.funct3)
                3'h0: branch_taken = zero;            //BEQ  (SUB deu zero)
                3'h1: branch_taken = ~zero;           //BNE  (SUB não deu zero)
                3'h4: branch_taken = alu_result[0];   //BLT  (SLT deu 1)
                3'h5: branch_taken = ~alu_result[0];  //BGE  (SLT deu 0)
                3'h6: branch_taken = alu_result[0];   //BLTU (SLTU deu 1)
                3'h7: branch_taken = ~alu_result[0];  //BGEU (SLTU deu 0)
                default: branch_taken = 1'b0;
            endcase
        end
    end

    pl_alu alu (
        .SrcA      (alu_srca),
        .SrcB      (alu_srcb),
        .Operation (ALU_CC),
        .ALUResult (alu_result),
        .Zero      (zero)
    );
    

    
    logic [31:0] jump_target;
    assign jump_target = id_ex.jalr ? ((alu_srca + id_ex.imm_ext) & 32'hFFFFFFFE) : (id_ex.pc + id_ex.imm_ext);

    logic take_branch_or_jump;
    assign take_branch_or_jump = branch_taken | id_ex.jump | id_ex.jalr;

    logic [31:0] ex_result_to_mem;
    logic [31:0] pc_plus_4;
    assign pc_plus_4 = id_ex.pc + 4;

    assign ex_result_to_mem = (id_ex.jump | id_ex.jalr) ? pc_plus_4 : alu_result;


    // Branch resolvido no estagio EX (flush 2 instrucoes se taken)
    assign branch_target = jump_target;
    assign pc_src        = take_branch_or_jump;

    // =========================================================================
    // Registrador EX/MEM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.mem_to_reg  <= 1'b0;
            ex_mem.reg_write   <= 1'b0;
            ex_mem.mem_read    <= 1'b0;
            ex_mem.mem_write   <= 1'b0;
            ex_mem.alu_result  <= 32'b0;
            ex_mem.write_data  <= 32'b0;
            ex_mem.rd          <= 5'b0;
            ex_mem.funct3      <= 3'b0;
        end else begin
            ex_mem.mem_to_reg  <= id_ex.mem_to_reg;
            ex_mem.reg_write   <= id_ex.reg_write;
            ex_mem.mem_read    <= id_ex.mem_read;
            ex_mem.mem_write   <= id_ex.mem_write;
            ex_mem.alu_result <= ex_result_to_mem;
            ex_mem.write_data  <= fwd_srcb;   // rs2 adiantado (para SW/MMIO)
            ex_mem.rd          <= id_ex.rd;
            ex_mem.funct3      <= id_ex.funct3;
        end
    end

    // =========================================================================
    // MEM -- Memoria de dados + MMIO
    // =========================================================================
    assign mmio_sel = ex_mem.alu_result[10];

    pl_dmem dmem (
        .clk       (clk),
        .MemWrite  (ex_mem.mem_write & ~mmio_sel),
        .addr      (ex_mem.alu_result[9:2]),
        .WriteData (mem_write_data_formatted),
        .ReadData  (dmem_rd)
    );

    pl_mmio mmio (
        .clk       (clk),
        .rst_n     (rst_n),
        .MemWrite  (ex_mem.mem_write &  mmio_sel),
        .MemRead   (ex_mem.mem_read  &  mmio_sel),
        .addr      (ex_mem.alu_result[4:2]),
        .WriteData (mem_write_data_formatted),
        .SW        (SW),
        .KEY       (KEY),
        .ReadData  (mmio_rd),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

    assign mem_read_data = mmio_sel ? mmio_rd : dmem_rd;



    //Lógica de formatação de LOAD (lb, lh, lw, lbu, lhu)
    always_comb begin
        //Padrão lw
        mem_read_data_formatted = mem_read_data; 
        
        if (ex_mem.mem_read) begin
            case (ex_mem.funct3)
                3'h0: begin //lb Extensão de Sinal
                    case (ex_mem.alu_result[1:0]) //bit 1:0 define qual byte
                        2'b00: mem_read_data_formatted = {{24{mem_read_data[7]}},  mem_read_data[7:0]};
                        2'b01: mem_read_data_formatted = {{24{mem_read_data[15]}}, mem_read_data[15:8]};
                        2'b10: mem_read_data_formatted = {{24{mem_read_data[23]}}, mem_read_data[23:16]};
                        2'b11: mem_read_data_formatted = {{24{mem_read_data[31]}}, mem_read_data[31:24]};
                    endcase
                end
                3'h1: begin //lh  Extensão de Sinal
                    case (ex_mem.alu_result[1]) //bit 1 define qual metade
                        1'b0: mem_read_data_formatted = {{16{mem_read_data[15]}}, mem_read_data[15:0]};
                        1'b1: mem_read_data_formatted = {{16{mem_read_data[31]}}, mem_read_data[31:16]};
                    endcase
                end
                3'h2: begin //lw (Load Word) é o padrão
                    mem_read_data_formatted = mem_read_data;
                end
                3'h4: begin //lbu (preenche com zeros porque é unsigned)
                    case (ex_mem.alu_result[1:0])
                        2'b00: mem_read_data_formatted = {24'b0, mem_read_data[7:0]};
                        2'b01: mem_read_data_formatted = {24'b0, mem_read_data[15:8]};
                        2'b10: mem_read_data_formatted = {24'b0, mem_read_data[23:16]};
                        2'b11: mem_read_data_formatted = {24'b0, mem_read_data[31:24]};
                    endcase
                end
                3'h5: begin //lhu (preenche com zeros porque é unsigned)
                    case (ex_mem.alu_result[1])
                        1'b0: mem_read_data_formatted = {16'b0, mem_read_data[15:0]};
                        1'b1: mem_read_data_formatted = {16'b0, mem_read_data[31:16]};
                    endcase
                end
                default: mem_read_data_formatted = mem_read_data;
            endcase
        end
    end




    //Lógica de formatação de STORE (sb, sh, sw)
    //Precisa passar os 32 bits (Read-Modify-Write), preservando o dado que já tinha e modificando a quantidade ncessária
    always_comb begin
        //Padrão: escreve a palavra inteira (sw)
        mem_write_data_formatted = ex_mem.write_data;

        if (ex_mem.mem_write) begin
            case (ex_mem.funct3)
                3'h0: begin //SB
                    case (ex_mem.alu_result[1:0]) //bit 1:0 define qual byte
                        2'b00: mem_write_data_formatted = {mem_read_data[31:8], ex_mem.write_data[7:0]};
                        2'b01: mem_write_data_formatted = {mem_read_data[31:16], ex_mem.write_data[7:0], mem_read_data[7:0]};
                        2'b10: mem_write_data_formatted = {mem_read_data[31:24], ex_mem.write_data[7:0], mem_read_data[15:0]};
                        2'b11: mem_write_data_formatted = {ex_mem.write_data[7:0], mem_read_data[23:0]};
                    endcase
                end
                3'h1: begin //SH
                    case (ex_mem.alu_result[1]) //bit 1 define qual metade
                        1'b0: mem_write_data_formatted = {mem_read_data[31:16], ex_mem.write_data[15:0]};
                        1'b1: mem_write_data_formatted = {ex_mem.write_data[15:0], mem_read_data[15:0]};
                    endcase
                end
                3'h2: begin //SW (Store Word) PADRAO
                    mem_write_data_formatted = ex_mem.write_data;
                end
                default: mem_write_data_formatted = ex_mem.write_data;
            endcase
        end
    end

    // Saidas de observabilidade para o testbench
    assign mem_wr_en   = ex_mem.mem_write & ~mmio_sel;
    assign mem_wr_addr = ex_mem.alu_result[9:2];
    assign mem_wr_data = ex_mem.write_data;

    // =========================================================================
    // Registrador MEM/WB
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb.mem_to_reg <= 1'b0;
            mem_wb.reg_write  <= 1'b0;
            mem_wb.alu_result <= 32'b0;
            mem_wb.read_data  <= 32'b0;
            mem_wb.rd         <= 5'b0;
        end else begin
            mem_wb.mem_to_reg <= ex_mem.mem_to_reg;
            mem_wb.reg_write  <= ex_mem.reg_write;
            mem_wb.alu_result <= ex_mem.alu_result;
            mem_wb.read_data  <= mem_read_data_formatted;
            mem_wb.rd         <= ex_mem.rd;
        end
    end

    // WB: wb_data = mem_to_reg ? read_data : alu_result  (definido acima, no bloco ID)

endmodule
