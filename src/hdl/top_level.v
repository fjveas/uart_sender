/*
 *
 */

`timescale 1ns / 1ps

module top_level
(
	input clk_100M,
	input reset_n,

	input uart_rx,
	output uart_tx,
	output uart_tx_alt,

	input button_c,
	input sw_mode,
	input [7:0] switches,

	output [7:0] ss_select,
	output [7:0] ss_value,

	output [2:0] rgb_led16,
	output led_mode,
	output [7:0] leds
);

	/*
	 * Convertir la señal del botón reset_n a 'active HIGH'
	 * y sincronizar con el reloj.
	 */
	reg [1:0] reset_sr;
	wire reset = reset_sr[1];
	always @(posedge clk_100M)
		reset_sr <= {reset_sr[0], ~reset_n};

	/* Apagar el display de 7 segmentos */
	assign ss_value = 8'hFF;
	assign ss_select = 8'hFF;

	/* Estados de la máquina */
	localparam S_IDLE    = 'b0001;
	localparam S_BEGIN   = 'b0010;
	localparam S_TX_DATA = 'b0100;
	localparam S_TX_WAIT = 'b1000;

	reg [3:0] state, state_next = S_IDLE;
	assign rgb_led16 = state[3:1];

	/* Señales de control y datos */
	wire tx_busy;
	reg tx_start = 1'b0;
	reg [7:0] tx_data, tx_data_next = 'd0;

	wire button_c_posedge;
	assign led_mode = sw_mode;
	assign leds = switches;

	/* Payload (11 chars) */
	localparam STR_LEN = 11;
	wire [STR_LEN*8-1:0] message = {
		8'h48, 8'h65, 8'h6c, 8'h6c, 8'h6f,
		8'h20,
		8'h77, 8'h6f, 8'h72, 8'h6c, 8'h64
	};

	/* Contador de bytes */
	reg [3:0] bcounter, bcounter_next = 'd0;

	/* Conectar el UART al Pmod JA */
	assign uart_tx_alt = uart_tx;

	/* Lógica combinacional */
	always @(*) begin
		tx_start = 1'b0;
		tx_data_next = tx_data;
		bcounter_next = bcounter;
		state_next = state;

		case (state)
		S_IDLE: begin
			if (button_c_posedge)
				state_next = S_BEGIN;
		end
		S_BEGIN: begin
			state_next = S_TX_DATA;
			bcounter_next = STR_LEN;

			if (sw_mode == 1'b1) begin
				tx_data_next = message[8*STR_LEN-1 -: 8];
			end else begin
				tx_data_next = switches[7:0];
			end
		end
		S_TX_DATA: begin
			state_next = S_TX_WAIT;
			tx_start = 1'b1;
			bcounter_next = bcounter - 'd1;
		end
		S_TX_WAIT: begin
			if (tx_busy == 1'b0) begin
				state_next = S_IDLE;
				tx_data_next = 8'h00;

				if (sw_mode == 1'b1 && bcounter != 0) begin
					state_next = S_TX_DATA;
					tx_data_next = message[(8 * bcounter - 1) -: 8];
				end
			end
		end
		default:
			state_next = S_IDLE;
		endcase
	end

	/* Lógica secuencial */
	always @(posedge clk_100M) begin
		if (reset) begin
			state <= S_IDLE;
			tx_data <= 'd0;
			bcounter <= 'd0;
		end else begin
			state <= state_next;
			tx_data <= tx_data_next;
			bcounter <= bcounter_next;
		end
	end

	/* Módulo UART a 115200/8N1 */
	uart_basic #(
		.CLK_FREQUENCY(100000000),
		.BAUD_RATE(115200)
	) uart_basic_inst (
		.clk(clk_100M),
		.reset(reset),
		.rx(uart_rx),
		.rx_data(),
		.rx_ready(),
		.tx(uart_tx),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy)
	);

	/* Debouncer */
	pb_debouncer #(
		.COUNTER_WIDTH(20)
	) pb_deb0 (
		.clk(clk_100M),
		.rst(reset),
		.pb(button_c),
		.pb_state(),
		.pb_negedge(),
		.pb_posedge(button_c_posedge)
	);

endmodule
