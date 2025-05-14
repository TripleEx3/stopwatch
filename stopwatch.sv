// 4-digit decimal counter module (0.000 to 9.999)
module decimal_counter(
    input  logic        clk,
    input  logic        reset_n,
    input  logic        clear,
    input  logic        enable,        // Counter enable from FSM (1KHz clock)
    input  logic        manual_increment, // Manual increment from FSM
    output logic [15:0] counter_value  // 4 BCD digits (4 bits each)
);
    // Internal signals for the individual digit counters
    logic [3:0] digit0; // 1ms digit (rightmost)
    logic [3:0] digit1; // 10ms digit
    logic [3:0] digit2; // 100ms digit
    logic [3:0] digit3; // 1000ms digit (leftmost)
    
    // Terminal count signals
    logic tc0;  // Terminal count for digit0
    logic tc1;  // Terminal count for digit1
    logic tc2;  // Terminal count for digit2
    logic tc3;  // Terminal count for digit3 (not used but included for completeness)
    
    // Terminal count detection (when digit reaches 9)
    assign tc0 = (digit0 == 4'b1001) & (enable | manual_increment);
    assign tc1 = (digit1 == 4'b1001) & tc0;
    assign tc2 = (digit2 == 4'b1001) & tc1;
    assign tc3 = (digit3 == 4'b1001) & tc2;
    
    // Digit 0 counter (1ms, least significant)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            digit0 <= 4'b0000;
        else if (clear)
            digit0 <= 4'b0000;
        else if (enable || manual_increment) begin
            if (digit0 == 4'b1001)
                digit0 <= 4'b0000;  // Roll over from 9 to 0
            else
                digit0 <= digit0 + 1'b1;
        end
    end
    
    // Digit 1 counter (10ms)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            digit1 <= 4'b0000;
        else if (clear)
            digit1 <= 4'b0000;
        else if (tc0) begin
            if (digit1 == 4'b1001)
                digit1 <= 4'b0000;  // Roll over from 9 to 0
            else
                digit1 <= digit1 + 1'b1;
        end
    end
    
    // Digit 2 counter (100ms)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            digit2 <= 4'b0000;
        else if (clear)
            digit2 <= 4'b0000;
        else if (tc1) begin
            if (digit2 == 4'b1001)
                digit2 <= 4'b0000;  // Roll over from 9 to 0
            else
                digit2 <= digit2 + 1'b1;
        end
    end
    
    // Digit 3 counter (1000ms)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            digit3 <= 4'b0000;
        else if (clear)
            digit3 <= 4'b0000;
        else if (tc2) begin
            if (digit3 == 4'b1001)
                digit3 <= 4'b0000;  // Roll over from 9 to 0
            else
                digit3 <= digit3 + 1'b1;
        end
    end
    
    // Combine all digits into the output
    assign counter_value = {digit3, digit2, digit1, digit0};
    
endmodule

// Clock divider module to generate 1KHz clock from system clock
module clock_divider #(
    parameter INPUT_FREQ = 100_000_000,  // Input frequency in Hz (default 100MHz)
    parameter OUTPUT_FREQ = 1_000        // Output frequency in Hz (1KHz for millisecond timing)
)(
    input  logic clk_in,     // Input clock
    input  logic reset_n,    // Active-low reset
    output logic clk_out     // Output clock
);
    // Calculate the divide value
    localparam DIVIDE_VALUE = INPUT_FREQ / OUTPUT_FREQ / 2;
    localparam COUNTER_WIDTH = $clog2(DIVIDE_VALUE);
    
    // Counter for clock division
    logic [COUNTER_WIDTH-1:0] counter;
    
    // Counter logic
    always_ff @(posedge clk_in or negedge reset_n) begin
        if (!reset_n) begin
            counter <= {COUNTER_WIDTH{1'b0}};
            clk_out <= 1'b0;
        end else begin
            if (counter == DIVIDE_VALUE - 1) begin
                counter <= {COUNTER_WIDTH{1'b0}};
                clk_out <= ~clk_out;  // Toggle output clock
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end
    
endmodule

// Finite State Machine module for the stopwatch
module stopwatch_fsm(
    input  logic        clk,
    input  logic        reset_n,
    input  logic        btn_start,    // Already debounced with edge detection
    input  logic        btn_stop,     // Already debounced with edge detection
    input  logic        btn_increment,// Already debounced with edge detection
    input  logic        btn_clear,    // Already debounced with edge detection
    output logic        counter_enable,
    output logic        manual_increment
);
    // Define the states
    typedef enum logic [1:0] {
        IDLE_STATE,     // Counter is stopped and displaying current value
        COUNTING_STATE, // Counter is running
        INCREMENT_STATE // Processing manual increment
    } state_t;
    
    // State registers
    state_t current_state, next_state;
    
    // State register update
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            current_state <= IDLE_STATE;
        else if (btn_clear)
            current_state <= IDLE_STATE; // Clear button resets to IDLE state
        else
            current_state <= next_state;
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state; // Default: stay in current state
        
        case (current_state)
            IDLE_STATE: begin
                if (btn_start)
                    next_state = COUNTING_STATE;
                else if (btn_increment)
                    next_state = INCREMENT_STATE;
            end
            
            COUNTING_STATE: begin
                if (btn_stop)
                    next_state = IDLE_STATE;
                // Note: In this implementation, if increment is pressed while counting,
                // we ignore it as it's not specified in the requirements
            end
            
            INCREMENT_STATE: begin
                // Return to IDLE after processing the increment
                next_state = IDLE_STATE;
            end
            
            default: next_state = IDLE_STATE;
        endcase
    end
    
    // Output logic
    always_comb begin
        // Default outputs
        counter_enable = 1'b0;
        manual_increment = 1'b0;
        
        case (current_state)
            IDLE_STATE: begin
                counter_enable = 1'b0;
                manual_increment = 1'b0;
            end
            
            COUNTING_STATE: begin
                counter_enable = 1'b1;
                manual_increment = 1'b0;
            end
            
            INCREMENT_STATE: begin
                counter_enable = 1'b0;
                manual_increment = 1'b1;
            end
            
            default: begin
                counter_enable = 1'b0;
                manual_increment = 1'b0;
            end
        endcase
    end
    
endmodule

// Button debouncer module
module button_debouncer #(
    parameter DEBOUNCE_CYCLES = 500_000  // Number of clock cycles for debouncing (5ms at 100MHz)
)(
    input  logic clk,         // System clock
    input  logic reset_n,     // Active-low reset
    input  logic btn_in,      // Raw button input
    output logic btn_out,     // Debounced button output
    output logic btn_edge     // Single-clock pulse on button press
);
    // Internal signals
    logic [19:0] counter;     // Counter for debounce timing
    logic btn_sync1, btn_sync2; // Synchronization flip-flops
    logic btn_current;        // Current stable button state
    logic btn_previous;       // Previous stable button state
    
    // Synchronize the button input to prevent metastability
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btn_sync1 <= 1'b0;
            btn_sync2 <= 1'b0;
        end else begin
            btn_sync1 <= btn_in;
            btn_sync2 <= btn_sync1;
        end
    end
    
    // Debounce logic
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 20'b0;
            btn_current <= 1'b0;
        end else begin
            // If the synchronized input is different from current stable state
            if (btn_sync2 != btn_current) begin
                // Reset counter when input changes
                counter <= 20'b0;
            end else if (counter < DEBOUNCE_CYCLES - 1) begin
                // Increment counter until threshold is reached
                counter <= counter + 1'b1;
            end else begin
                // Input is stable for DEBOUNCE_CYCLES, update current state
                btn_current <= btn_sync2;
            end
        end
    end
    
    // Edge detection
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btn_previous <= 1'b0;
            btn_edge <= 1'b0;
        end else begin
            btn_previous <= btn_current;
            // Rising edge detection (button press)
            btn_edge <= btn_current & ~btn_previous;
        end
    end
    
    // Assign debounced output
    assign btn_out = btn_current;
    
endmodule

// Seven-segment display controller module
module seven_segment_controller(
    input  logic        clk,
    input  logic        reset_n,
    input  logic [15:0] bcd_in,       // 4 BCD digits (4 bits each)
    output logic [6:0]  seg,          // Seven-segment display segments (active low)
    output logic [3:0]  an            // Anode select (active low)
);
    // Constants for seven-segment display patterns (active low)
    // Segments: 6 = g, 5 = f, 4 = e, 3 = d, 2 = c, 1 = b, 0 = a
    logic [6:0] seven_seg_patterns [10] = '{
        7'b1000000,  // 0
        7'b1111001,  // 1
        7'b0100100,  // 2
        7'b0110000,  // 3
        7'b0011001,  // 4
        7'b0010010,  // 5
        7'b0000010,  // 6
        7'b1111000,  // 7
        7'b0000000,  // 8
        7'b0010000   // 9
    };
    
    // Counter for display multiplexing
    logic [1:0] digit_select;
    logic [16:0] refresh_counter;  // Counter for display refresh rate
    
    // Refresh counter for multiplexing the displays
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            refresh_counter <= 17'b0;
        else
            refresh_counter <= refresh_counter + 1'b1;
    end
    
    // Use the MSBs of the refresh counter to select the display
    assign digit_select = refresh_counter[16:15];  // Change this to adjust refresh rate
    
    // BCD digit extraction
    logic [3:0] bcd_digit;
    logic dp; // Decimal point (active low)
    
    // Select the active digit based on digit_select
    always_comb begin
        case(digit_select)
            2'b00: begin
                an = 4'b1110;  // Enable rightmost digit (1ms)
                bcd_digit = bcd_in[3:0];  // digit0
                dp = 1'b1;     // Decimal point off
            end
            2'b01: begin
                an = 4'b1101;  // Enable 2nd digit from right (10ms)
                bcd_digit = bcd_in[7:4];  // digit1
                dp = 1'b1;     // Decimal point off
            end
            2'b10: begin
                an = 4'b1011;  // Enable 3rd digit from right (100ms)
                bcd_digit = bcd_in[11:8];  // digit2
                dp = 1'b1;     // Decimal point off
            end
            2'b11: begin
                an = 4'b0111;  // Enable leftmost digit (1000ms)
                bcd_digit = bcd_in[15:12];  // digit3
                dp = 1'b0;     // Decimal point on (between seconds and milliseconds)
            end
            default: begin
                an = 4'b1111;  // All off
                bcd_digit = 4'b0000;
                dp = 1'b1;     // Decimal point off
            end
        endcase
    end
    
    // Output logic for 7-segment display
    logic [7:0] segment_with_dp;
    
    // Combine the 7-segment pattern with the decimal point
    assign segment_with_dp = {dp, seven_seg_patterns[bcd_digit]};
    
    // Output the 7-segment pattern (without decimal point)
    assign seg = seven_seg_patterns[bcd_digit];
    
endmodule

// Top-level module for the stopwatch system
module stopwatch(
    input  logic        clk,          // System clock
    input  logic        reset_n,      // Active-low reset
    input  logic        btn_start,    // Start button
    input  logic        btn_stop,     // Stop button
    input  logic        btn_increment,// Increment button
    input  logic        btn_clear,    // Clear/reset button
    output logic [6:0]  seg,          // Seven-segment display segments
    output logic [3:0]  an            // Seven-segment display anode select
);
    // Internal signals
    logic [15:0]    counter_value;   // 4-digit decimal counter value (16 bits for 4 BCD digits)
    logic           counter_enable;   // Enable signal for the counter
    logic           manual_increment; // Increment signal from button debouncer
    logic           clk_1khz;        // 1KHz clock for millisecond timing
    
    // Debounced button signals
    logic btn_start_db, btn_start_edge;
    logic btn_stop_db, btn_stop_edge;
    logic btn_increment_db, btn_increment_edge;
    logic btn_clear_db, btn_clear_edge;
    
    // Instantiate the clock divider (assuming 100MHz system clock)
    clock_divider #(
        .INPUT_FREQ(100_000_000),  // 100MHz system clock (adjust as needed)
        .OUTPUT_FREQ(1_000)        // 1KHz output for millisecond timing
    ) ms_clock_gen (
        .clk_in(clk),
        .reset_n(reset_n),
        .clk_out(clk_1khz)
    );
    
    // Instantiate button debouncers
    button_debouncer start_debouncer (
        .clk(clk),
        .reset_n(reset_n),
        .btn_in(btn_start),
        .btn_out(btn_start_db),
        .btn_edge(btn_start_edge)
    );
    
    button_debouncer stop_debouncer (
        .clk(clk),
        .reset_n(reset_n),
        .btn_in(btn_stop),
        .btn_out(btn_stop_db),
        .btn_edge(btn_stop_edge)
    );
    
    button_debouncer increment_debouncer (
        .clk(clk),
        .reset_n(reset_n),
        .btn_in(btn_increment),
        .btn_out(btn_increment_db),
        .btn_edge(btn_increment_edge)
    );
    
    button_debouncer clear_debouncer (
        .clk(clk),
        .reset_n(reset_n),
        .btn_in(btn_clear),
        .btn_out(btn_clear_db),
        .btn_edge(btn_clear_edge)
    );
    
    // Instantiate the state machine
    stopwatch_fsm fsm (
        .clk(clk_1khz),  // Use 1KHz clock for FSM
        .reset_n(reset_n),
        .btn_start(btn_start_edge),
        .btn_stop(btn_stop_edge),
        .btn_increment(btn_increment_edge),
        .btn_clear(btn_clear_edge),
        .counter_enable(counter_enable),
        .manual_increment(manual_increment)
    );
    
    // Instantiate the 4-digit decimal counter
    decimal_counter counter (
        .clk(clk_1khz),  // Use 1KHz clock for counter
        .reset_n(reset_n),
        .clear(btn_clear_edge),
        .enable(counter_enable),
        .manual_increment(manual_increment),
        .counter_value(counter_value)
    );
    
    // Instantiate the seven-segment display controller
    seven_segment_controller display_ctrl (
        .clk(clk),      // Use system clock for display multiplexing
        .reset_n(reset_n),
        .bcd_in(counter_value),
        .seg(seg),
        .an(an)
    );
    
endmodule
