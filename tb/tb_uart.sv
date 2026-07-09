`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// 1. INTERFACE
//_______________________________________________________
interface uart_if(input logic clk);
    logic        rst;
    logic        tx_start;
    logic [7:0]  tx_data;
    logic        tx_out;
    logic        tx_done;
    logic [7:0]  rx_data;
    logic        rx_done;

// Concurrent Assertions
// Rule 1: tx_done remains high for 1 clk cycle
  property prop_txdone_pulse;
    @(posedge clk) disable iff (rst)
        $rose(tx_done) |=> !tx_done;
 endproperty
    A1_txdone: assert property (prop_txdone_pulse)
        else $error("ASSERTION FAIL A1: tx_done held HIGH for more than 1 cycle");

// Rule 2: rx_done remains high for 1 clk cycle
    property prop_rxdone_pulse;
        @(posedge clk) disable iff (rst)
        $rose(rx_done) |=> !rx_done;
    endproperty
    A2_rxdone: assert property (prop_rxdone_pulse)
        else $error("ASSERTION FAIL A2: rx_done held HIGH for more than 1 cycle");

// Rule 3: tx_done and tx_start should never stay high together
    property prop_no_overlap;
        @(posedge clk) disable iff (rst)
        tx_done |-> !tx_start;
    endproperty
    A3_overlap: assert property (prop_no_overlap)
        else $error("ASSERTION FAIL A3: tx_done and tx_start overlap detected");

endinterface
//__________________________________________________________
// 2. SEQUENCE ITEM
//__________________________________________________________
class uart_seq_item extends uvm_sequence_item;
    `uvm_object_utils(uart_seq_item)

    rand bit [7:0] data;

    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction

endclass

//__________________________________________________________
// 3. SEQUENCE
//__________________________________________________________
class uart_sequence extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_sequence)

    function new(string name = "uart_sequence");
        super.new(name);
    endfunction

    task body();
        uart_seq_item item;
        bit [7:0] test_vals[5] = '{
            8'h41,   //Normal character 'A'
            8'h00,   //All zeros
            8'hFF,   //All ones
            8'h55,   //01010101
            8'hAA    //10101010
        };

        foreach(test_vals[i]) begin
            item = uart_seq_item::type_id::create("item");
            start_item(item);
            item.data = test_vals[i];
            finish_item(item);
        end
    endtask

endclass
//__________________________________________________________
// 4. DRIVER
//__________________________________________________________
class uart_driver extends uvm_driver #(uart_seq_item);
    `uvm_component_utils(uart_driver)

    virtual uart_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db #(virtual uart_if)::get(
            this, "", "uart_vif", vif))
            `uvm_fatal("DRV", "Virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        uart_seq_item req;

        //initialization
        vif.tx_start = 0;
        vif.tx_data  = 0;

        forever begin
           seq_item_port.get_next_item(req);
           uart_scoreboard::exp_mbx.put(req.data);
          
            @(posedge vif.clk);
            vif.tx_data  <= req.data;
            vif.tx_start <= 1'b1;

            @(posedge vif.clk);
            vif.tx_start <= 1'b0;
            @(posedge vif.rx_done);
            #100;
          
            seq_item_port.item_done();
        end
    endtask

endclass
//__________________________________________________________
// 5. MONITOR
//__________________________________________________________
class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    virtual uart_if vif;

    // TLM analysis port
    uvm_analysis_port #(uart_seq_item) ap;

    // Functional Coverage
    covergroup cg_uart;
      
      //Coverpoint 1: recieved data range
        cp_data: coverpoint vif.rx_data {
            bins zero     = {8'h00};   // All zeros
            bins all_ones = {8'hFF};   // All ones
            bins alt_01   = {8'h55};   // 01010101
            bins alt_10   = {8'hAA};   // 10101010
            bins others   = default;  
        }

        //Coverpoint 2: rx_done
        cp_rxdone: coverpoint vif.rx_done {
            bins got_done = {1'b1};    
        }

    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_uart = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if(!uvm_config_db #(virtual uart_if)::get(
            this, "", "uart_vif", vif))
            `uvm_fatal("MON", "Virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        uart_seq_item pkt;

        forever begin
            @(posedge vif.rx_done);
            #1;

            //Sample coverage on received byte
            cg_uart.sample();

          //Capture observed data & send to scoreboard
            pkt = uart_seq_item::type_id::create("pkt");
            pkt.data = vif.rx_data;
            ap.write(pkt);
        end
    endtask

    //funcn cvrg summary
    function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf(
            "\nFUNCTIONAL COVERAGE: %0.2f%%",
            cg_uart.get_coverage()), UVM_LOW)
    endfunction

endclass
//__________________________________________________________
// 6.SCOREBOARD
//__________________________________________________________
class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)

    //TLM analysis imp
    uvm_analysis_imp #(uart_seq_item, uart_scoreboard) analysis_export;

    static mailbox #(bit [7:0]) exp_mbx = new();

    int pass_count = 0;
    int fail_count = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    function void write(uart_seq_item item);
        bit [7:0] exp_data;
   if(!exp_mbx.try_get(exp_data)) begin
    `uvm_error("SB", "Received data but expected mailbox is empty")
    return;
      end
        //Immediate assertion
        assert (^item.data !== 1'bx)
            else `uvm_error("SB",
                "ASSERTION FAIL A4: Received data contains unknown X or Z bits")

        //Compare received and expected data
        if(item.data === exp_data) begin
       `uvm_info("SB", $sformatf(
        "PASSED | Sent: 0x%0h | Received: 0x%0h",
        exp_data, item.data), UVM_LOW)
            pass_count++;
        end
        else begin
            `uvm_error("SB", $sformatf(
"FAILED | Sent: 0x%0h | Got: 0x%0h - Data mismatch detected",
                exp_data, item.data))
            fail_count++;
        end
    endfunction

    //report
    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf(
            "\nRESULTS: %0d PASSED | %0d FAILED\n",
            pass_count, fail_count), UVM_LOW)
    endfunction

endclass
//__________________________________________________________
// 7. AGENT
//__________________________________________________________
class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)

    uart_driver                     driver;
    uart_monitor                    monitor;
    uvm_sequencer #(uart_seq_item)  sequencer;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = uart_driver::type_id::create("driver", this);
        monitor   = uart_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer #(uart_seq_item)::type_id::create(
                    "sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        //Connect driver to sequencer
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
//__________________________________________________________
// 8. ENVIRONMENT
//__________________________________________________________
class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)

    uart_agent      agent;
    uart_scoreboard sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = uart_agent::type_id::create("agent", this);
        sb    = uart_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Connect monitor analysisPort to scoreboard
        agent.monitor.ap.connect(sb.analysis_export);
    endfunction

endclass
//__________________________________________________________
// 9. TEST
//__________________________________________________________
class uart_test extends uvm_test;
    `uvm_component_utils(uart_test)

    uart_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_sequence seq;

        //prevent simulation from ending
        phase.raise_objection(this);

        // Create and start sequence on agent sequencer
        seq = uart_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);

        #100;

      // Drop objection simulation may end now
        phase.drop_objection(this);
    endtask

endclass
//__________________________________________________________
// 10. TOP MODULE
//__________________________________________________________
module uart_tb_top;

    logic clk;
    initial clk = 0;
    always #10 clk = ~clk;

    uart_if vif(.clk(clk));

    //UART transmitter
    uart_tx DUT_TX (
        .clk      (clk),
        .rst      (vif.rst),
        .tx_start (vif.tx_start),
        .tx_data  (vif.tx_data),
        .tx_out   (vif.tx_out),
        .tx_done  (vif.tx_done)
    );

    //UART reciever
    // Loopback:tx_out->rx_in
    uart_rx DUT_RX (
        .clk     (clk),
        .rst     (vif.rst),
        .rx_in   (vif.tx_out),
        .rx_data (vif.rx_data),
        .rx_done (vif.rx_done)
    );

     //config_db at time 0
     initial begin
     uvm_config_db #(virtual uart_if)::set(
        null, "uvm_test_top.*", "uart_vif", vif);
end

//run_test at time 0
initial begin
    run_test("uart_test");
end

// rsr sqenc
initial begin
    vif.rst      = 1;
    vif.tx_start = 0;
    vif.tx_data  = 0;
    repeat(5) @(posedge clk);
    vif.rst = 0;
end
endmodule
endmodule
