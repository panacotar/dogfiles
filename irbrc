begin
  require 'rubygems'
  require 'pry'
rescue LoadError
end

# Exit with `q`
alias q exit

module Kernel
    def q
        exit
    end
end

# bindkey '^H' backward-kill-word

# Reloads the irb console 
def reload_irb
  load File.expand_path("~/.irbrc")
  reload! if @script_console_running
  puts "Reloaded"
end

# Copy string to clipboard
def clip(string)
  `echo "#{string}" | pbcopy`
  puts "copied in clipboard"
end

# if defined?(Pry)
#   Pry.start
#   exit
# end


