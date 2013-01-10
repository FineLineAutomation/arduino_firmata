module ArduinoFirmata

  class Arduino

    attr_reader :version, :status

    def initialize(serial_name, params)
      @status = Status::CLOSE
      @wait_for_data = 0
      @execute_multi_byte_command = 0
      @multi_byte_channel = 0
      @stored_input_data = []
      @parsing_sysex = false
      @sysex_bytes_read = nil

      @digital_output_data = Array.new(16, 0)
      @digital_input_data = Array.new(16, 0)
      @analog_input_data = Array.new(16, 0)

      @version = nil

      @on_analog_changed = []

      @serial = SerialPort.new(serial_name, params[:bps], params[:bit], params[:stopbit], params[:parity])
      @serial.read_timeout = 3
      sleep 3
      @status = Status::OPEN

      trap 'SIGHUP' do
        close
        exit
      end
      trap 'SIGINT' do
        close
        exit
      end
      trap 'SIGKILL' do
        close
        exit
      end
      trap 'SIGTERM' do
        close
        exit
      end

      @thread_status = false
      Thread.new{
        @thread_status = true
        while status == Status::OPEN do
          process_input
          sleep 0.01
        end
        @thread_status = false
      }.run

      0.upto(params[:analog_input_pins]-1).each do |i|
        write(REPORT_ANALOG | i)
        write 1
      end
      0.upto(1).each do |i|
        write(REPORT_DIGITAL | i)
        write 1
      end

      write REPORT_VERSION
      loop do
        break if @version
        sleep 0.3
      end
      sleep 0.5
    end

    def close
      return if status == Status::CLOSE
      @status = Status::CLOSE
      @serial.close
      loop do
        if @serial.closed? and @thread_status != true
          break
        end
        sleep 0.01
      end
    end

    def reset
      write SYSTEM_RESET
    end

    def digital_read(pin)
      (@digital_input_data[pin >> 3] >> (pin & 0x07)) & 0x01 > 0
    end

    def analog_read(pin)
      @analog_input_data[pin]
    end

    def pin_mode(pin, mode)
      write SET_PIN_MODE
      write pin
      mode = case mode
             when true
               OUTPUT
             when false
               INPUT
             else
               mode
             end
      if write(mode) == 1
        return mode
      end
    end

    def digital_write(pin, value)
      pin_mode pin, OUTPUT
      port_num = (pin >> 3) & 0x0F
      if value == 0 or value == false
        @digital_output_data[port_num] &= ~(1 << (pin & 0x07))
      else
        @digital_output_data[port_num] |= (1 << (pin & 0x07))
      end

      write(DIGITAL_MESSAGE | port_num)
      write(@digital_output_data[port_num] & 0x7F)
      if write(@digital_output_data[port_num] >> 7) == 1
        return value
      end
    end

    def analog_write(pin, value)
      pin_mode pin, PWM
      write(ANALOG_MESSAGE | (pin & 0x0F))
      write(value & 0x7F)
      if write(value >> 7) == 1
        return value
      end
    end

    def servo_write(pin, angle)
      pin_mode pin, SERVO
      write(ANALOG_MESSAGE | (pin & 0x0F))
      write(angle & 0x7F)
      if write(angle >> 7) == 1
        return angle
      end
    end

    private
    def write(cmd)
      return if status == Status::CLOSE
      @serial.write_nonblock cmd.chr
    end

    def read
      return if status == Status::CLOSE
      @serial.read_nonblock 9600 rescue EOFError
    end

    def process_input
      StringIO.new(String read).bytes.each do |input_data|
        command = nil

        if @parsing_sysex
          if input_data == END_SYSEX
            @parsing_sysex = FALSE
          else
            @stored_input_data[@sysex_bytes_read] = input_data
            @sysex_bytes_read += 1
          end
        elsif @wait_for_data > 0 and input_data < 128
          @wait_for_data -= 1
          @stored_input_data[@wait_for_data] = input_data
          if @execute_multi_byte_command != 0 and @wait_for_data == 0
            case @execute_multi_byte_command
            when DIGITAL_MESSAGE
              @digital_input_data[@multi_byte_channel] = (@stored_input_data[0] << 7) + @stored_input_data[1]
            when ANALOG_MESSAGE
              analog_value = (@stored_input_data[0] << 7) + @stored_input_data[1]
              unless @analog_input_data[@multi_byte_channel] == analog_value
                on_analog_changed @multi_byte_channel, analog_value
              end
              @analog_input_data[@multi_byte_channel] = analog_value
            when REPORT_VERSION
              @version = "#{@stored_input_data[1]}.#{@stored_input_data[0]}"
            end
          end
        else
          if input_data < 0xF0
            command = input_data & 0xF0
            @multi_byte_channel = input_data & 0x0F
          else
            command = input_data
          end
          if [DIGITAL_MESSAGE, ANALOG_MESSAGE, REPORT_VERSION].include? command
            @wait_for_data = 2
            @execute_multi_byte_command = command
          end
        end
      end
    end
    
  end
  
end
