module Pipes
  module Utils
    def self.constantize(str)
      str.split('::').reject(&:empty?).inject(Kernel) { |const, name| const.const_get(name) }
    end 
  end
end