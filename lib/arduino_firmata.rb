$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'serialport'
require 'eventmachine'
require 'stringio'
require 'arduino_firmata/main'
require 'arduino_firmata/const'
require 'arduino_firmata/arduino'
require 'arduino_firmata/event'

module ArduinoFirmata
  VERSION = '0.1.5'
end
