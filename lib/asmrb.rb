require 'pry'
require 'colorize'
require 'llvm/core'
require 'benchmark'
require 'llvm/execution_engine'
require 'llvm/transforms/scalar'

# You can make an instruction-based function with high level ruby by this Asm class.
class Asmrb
  # Sample with recursion:
  #
  # Asmrb.new do
  #   fun :rec_print      # define a function, also a label to jump.
  #   arg arr             # arguments
  #   push 0              # get value to l variable
  #   len arr             # get length of arr as array
  #   cmp                 # is l > 0 ?
  #   jge :print          # then jump to :print block
  #   jmp :exit           # else, jump to :exit block
  #   label :print        # start of :print
  #   car arr             # get out first element of arr
  #   call :puts          # call ruby's puts
  #   cdr arr             # get rest of arr Array
  #   recur               # jump back to :rec_print ( or start of this function )
  #   label :exit         # ending label.
  # end
  # => $rec_print
  #
  # debug:
  # => $rec_print.is_debug = true
  #
  # invoking:
  # => $rec_print.invoke [1,2,3]
  # 
  # calling:
  # => rec_print [1,2,3]
  #

  attr_reader :variables, :stack, :source, :ruby_source, :name, :result, :params, :is_debug, :extension
  attr_writer :is_debug

  def initialize &block
    new_scope
    assemble &block unless block.nil?
  end

  def eval_file path
    source = File.read path
    eval_source source
  end

  def eval_source source
    new_scope
    puts source.light_yellow
    eval <<-CODE
    assemble do
      #{source}
    end
    CODE
    compiled = to_ruby
    puts compiled.magenta
    eval compiled
  end

  def compiled?
    !@ruby_source.nil?
  end

  def invoke *args
    arguments args
    execute is_debug
  end

  def to_ruby
    # need parititioning first..
    partition
    unless @partitions.empty?
      @ruby_source = Array.new
      block_labels = @partitions.map &:first
      @entry_point = @partitions.first.first 
      @partitions.each.with_index do |partition, index|  
      define_block partition, index, block_labels
      end
      @ruby_source = @ruby_source.join "\n"
    end
  end

  def all_ops
    OPS.map do |k,v|
      ops_info k
    end
  end

  def all_opcodes
    puts "[OPCODES] check:".green
    OPS.map do |k, v|
      check = OPCODES.include?(k.to_sym) ? :implemented : :not_yet
      report = ""
      case check
      when :implemented
        report = "#{k} => #{check}".light_green
      when :not_yet
        report = "#{k} => #{check}".light_yellow
      end
      puts report
    end
    puts "-------------------------".green
  end

  def new_instruction key, block
    @extension[key] = block
  end

  def extend_program &block
    self.instance_exec &block
  end

  def patch_line number, block=[]
    @source.insert number, block
    puts "patched at line #{number}: #{block}".light_green
    rebuild_source
  end

  def remove_line line_number
    puts "remove line #{line_number}: #{@source[line_number]}".light_yellow
    @source.delete_at line_number
    rebuild_source
  end

  def rebuild_source
    @source.each do |statement|
      build_statement statement.first, statement.last
    end
  end

  private
  def new_scope
    @variables = Hash.new
    @source = Array.new
    @ruby_source = Array.new
    @program = Array.new
    @params = 0
    @name = "it"
    @labels = Hash.new
    @stack = Array.new
    @pc = 0
    @result = nil
    @is_debug = false
    @compile_stack = Array.new
    @extension = Hash.new
  end

  def define_block partition, index, block_labels
    func = partition.first
    body = partition.last
    args = body.first.first.to_sym == :arg ? body.first.last.join(', ') : "" 
    
    block = Array.new
    block << "def #{func} #{args}"
    indent = " " * 2
    
    body.each do |statement|
      # process statement here.
      puts statement.to_s if @is_debug
      if OPCODES.include? statement[0].to_sym
        segment = self.instance_exec *statement[1], &OPCODES[statement[0].to_sym]
        #binding.pry
        block << (indent + segment.to_s) unless segment.nil?
      else
        puts "[define_block] Undefined OPCODE: #{statement[0]}\nAt: #{func}: #{statement}".red
      end
    end
    
    make_jump_on_next block, block_labels, index, body

    finalize_block block
  end

  def make_jump_on_next block, block_labels, index, body
    # leave pointer of next function here:
    if index != block_labels.length-1 && ![:rec, :ret, :exi].include?(body.last[0].to_sym)
      func = block_labels[index+1] 
      body = @partitions[func].first
      #binding.pry
      if body.first.to_sym == :arg
        args = "#{body.last.join(', ')}"
        block << "  #{func} #{args}"
      else
        block << "  #{func}"
      end
    end
  end

  def finalize_block block
    block << "end\n"
    @ruby_source << block.join("\n")
    
    if @is_debug
      puts @source.last.join(" ").light_yellow 
      puts "-------------------" 
    end
  end

  def refvar val
    val.is_a?(Symbol) ? @variables[val] : val
  end

  def req_type(f,types)
    s = types.is_a?(Array) ? types.join(', ') : types
    raise Exception.new "[#{f}] got problem with #{lst}. need to be #{s}."
  end

  def req_args(func,amount)
    raise Exception.new "[#{func}]: require #{amount} args to compare." if @stack.length < amount
  end

  OPS = {
    :slp => lambda { |amount| sleep amount},
    :los => lambda { | args |
                args = @variables[args] if @variables.include?(args) 
                args.reverse.each {|arg| @stack.push arg}
              },

    :lea => lambda { | name |
                @variables[name] = @stack.pop
              },

    :len => lambda { | lst |
                @stack.push @variables[lst].length
              },

    :cdr => lambda { | lst |
                @stack.push @variables[lst].drop 1
              },

    :car => lambda { | lst |
                @stack.push @variables[lst].first
              },

    :map => lambda { | ops |
                eval "@stack.map(&:#{ops})"
              },

    :red => lambda { | ops |
                e = eval "@stack.reduce(:#{ops})"
                @stack.clear
                @stack.push e
              },

    :dpl => lambda {
                @stack.push @stack.last
              },

    :add => lambda { @stack.push @stack.pop + @stack.pop },
    :sub => lambda { @stack.push @stack.pop - @stack.pop },
    :mul => lambda { @stack.push @stack.pop * @stack.pop },
    :div => lambda { @stack.push @stack.pop / @stack.pop },

    :icr => lambda { |dest, val = 1|  @variables[dest] += val },
    :dcr => lambda { |dest, val = 1| @variables[dest] -= val },

    :mov => lambda { | src , dest |
                @variables[dest] =
                  src.is_a?(Symbol) ?
                      @variables[src] : src
              },

    :jnl => lambda { | name |
                req_args "jnl", 1
                @pc = @labels[name] if @stack.pop.nil?
              },

    :jz => lambda { | name |
                req_args "jz", 1
                @pc = @labels[name] if @stack.pop == 0
              },

    :jnz => lambda { | name |
                req_args "jnz", 1
                @pc = @labels[name] if @stack.pop != 0
              },

    :jge => lambda { |name|
                req_args "jge", 2
                @pc = @labels[name] if @stack.pop > @stack.pop
              },

    :jlt => lambda { |name|
                req_args "jlt", 2
                @pc = @labels[name] if @stack.pop < @stack.pop
              },

    :jeq => lambda { |name|
                req_args "jeq", 2
                @pc = @labels[name] if @stack.pop == @stack.pop
              },

    :jmp => lambda { |name|
                @pc = @labels[name]
                new_title "[#{name}]" if @is_debug
              },

    :pop => lambda {|val|
                @stack.pop
              },

    :psh => lambda {|src|
                @stack.push(
                  src.is_a?(Symbol) ? @variables[src] : src )
              },

    :arg => lambda { |*args|
                if @stack.length < args.length
                  raise Exception.new "require (#{args.join(', ')}) on stack: #{@stack}"
                else
                  args.reverse.each do | arg |
                    @variables[arg] = @stack.pop
                  end
                end
              },

    :req => lambda {|amount|
                raise Exception.new "require #{amount} arg." if @stack.length < amount
              },

    :dbg => lambda {
                puts "#{@stack} > #{@program[@pc][0]}".light_green
                binding.pry if @is_debug
              },

    :inv => lambda { |obj, f|
                args = Array.new
                @stack.each { args << @stack.pop } if @stack.length > 0
                if args.length > 0
                  @stack.push @variables[obj].send(f, eval("args.join(', ')")) 
                else
                  @stack.push @variables[obj].send f
                end
              },

    :cal => lambda {|fname|
                _method = method fname
                if _method && _method.parameters.length > 0
                  args = Array.new
                  _method.parameters.length.times do
                    args.push @stack.pop
                  end
                  invoke = _method.call args
                else
                  invoke = _method.call
                end
                @stack.push invoke if !invoke.nil?
              },
    :rec => lambda {
                @pc = -1
              },

    :ret => lambda {
                @pc = @program.length-1
              },

    :exi => lambda {
                exit
              }
  }

  def create_label blo
    @labels[blo] = @program.length-1
    puts "#{@label[blo]}: #{blo}".purple if @is_debug
  end

  def method_missing name, *args
    build_statement name, *args
  end

  def build_statement name, *args
    # save source
    @source << [name, args]

    # :_name => :name
    name = name.to_s.gsub("_", "").to_sym

    if OPS.keys.include? name
      @program << [name, args]
      # get parameter amount:
      @params = args.length if name == :arg
    else
      case name

      when :blo
        create_label args.first

      when :fun
        @name = args.first
        create_label @name

      else
        return name
      end
    end
  end

  def execute debug=false
    new_line if debug
    puts "#{@stack} > #{@name}".yellow  if debug
    begin
      @pc = 0
      until @pc == @program.length
        # get instruction:
        instr = @program[@pc]
        puts "#{@pc}: #{instr[0]} #{instr[1].join " "}".light_green if debug
        # execute proc: arg ,  proc
        self.instance_exec *instr[1], &OPS[instr[0]]
        @pc += 1
      end
      #binding.pry
      @result = @stack.last
      clear
    rescue Exception => e
      debug e, instr
    end
    new_line if debug
    @result
  end

  def fast_execute *args
    arguments args
    @pc = 0
    until @pc == @program.length
      # execute proc:
      self.instance_exec *@program[@pc].last,
                         &OPS[@program[@pc].first]
      @pc += 1
    end
    @result = @stack.last
    clear
    @result
  end

  def new_title title
    puts "\n::#{title}"
  end

  def new_line
    puts "\n----------------------"
  end

  def debug e, instr
    if @pc.nil? || instr.nil?
      puts "possible null jump:".red
      binding.pry
    end
    puts "\n--------[BUG]---------"
    # error scope:
    scope_begin = @pc >= 1 ? @pc - 1 : 0
    scope_end = @pc <= (@program.length - 2) ? @pc + 1  : @pc
    # ranging...
    (scope_begin..scope_end).each do | i |
      instr = @program[i]
      color = i != @pc ?  :light_green : :magenta
      puts "#{i}: #{instr[0]} #{instr[1]}".colorize color
    end
    unless instr.nil?
      puts "\nat line #{@pc}:" +
           "#{ops_info(@program[@pc][0])}" +
           "has #{e.message}".colorize(:magenta)
    end
    binding.pry if is_debug
  end

  def ops_info name
    return if OPS[name].nil?
    parameters = Array.new
    OPS[name].parameters.each do |pair|
      parameters << pair.last
    end
    "#{name} [#{parameters.join(', ')}]"
  end

  def arguments args=[]
    args.each do | arg |
      @stack << arg
    end
  end

  def clear
    @pc = 0
    @variables = { }
    @stack = []
  end

  def assemble &block
    extend_program &block
    eval "$#{@name} = self.clone"
    eval "$#{@name}"
  end

  def collect_label_arg label
    if @program[label.last+1].first.to_sym == :arg
      @labels_arg[label.first] = @program[label.last+1].last
    end
  end

  def partition
    puts "partitioning...".light_green if@is_debug
    if @labels.empty?
      @partitions = { @name => @program }
    else
      @partitions = Hash.new
      @labels_arg = Hash.new
      @limitation = 0
      @jump_points = @labels.map &:last
      @labels.each.with_index do |label, label_index| 
        collect_label_arg label
        # to save all args with a :blo ;)

        if label_index != @jump_points.length-1
          @limitation = @jump_points[label_index+1] 
        else
          @limitation = @program.length-1 
        end
        puts "#{label[1]+1}:#{label[0]}".magenta
        partition = Array.new
        # binding.pry
        code_segment = @program[label.last+1..@limitation]
        code_segment.each.with_index do |statement, index|
          partition << statement

          puts (read_internal statement, index).light_yellow if @is_debug
        end
        @partitions[label.first] = partition.dup
      end
    end
    puts "partitioning completed.".light_green
    @partitions if@is_debug
  end

  def read_internal instruction, index
    "  #{index}: #{instruction.first}" +
    " #{instruction.last.join(" ") unless instruction.last.empty?}"          
  end
  
  def patched_arg label
    "#{label} #{@labels_arg[label].join(', ') if @labels_arg.include?(label)}"
  end

  def opcode_operator op
    @compile_stack.push "#{@compile_stack.pop} #{op} #{@compile_stack.pop}" if @compile_stack.length > 1
    nil
  end

  def cond_jump op, label
    return "if #{@compile_stack.pop} #{op} #{@compile_stack.pop}\n    #{patched_arg label}\n  end" if @compile_stack.length > 1
    nil            
  end

  def sole_cond_jump op, label
    return "if #{@compile_stack.pop}#{op}\n    #{patched_arg label}\n end" unless @compile_stack.empty?
    nil
  end

  def fetch statement
    @compile_stack << statement
  end

  OPCODES = {
    :sleep => lambda {|amount| "sleep #{amount}"},
    :dbg => lambda {"binding.pry"},
    :req => lambda {|_|},
    
    :map => lambda {|op| "#{@compile_stack}.map &:#{op}" },
    :red => lambda {|op| "#{@compile_stack}.reduce :#{op}" },
    
    :pop => lambda { @compile_stack.pop },
    :icr => lambda {|arg| fetch "#{arg} = #{arg} + 1" },
    :dcr => lambda {|arg| fetch "#{arg} = #{arg} - 1" },

    :mov => lambda {|src, dest| "#{dest} = #{src}" },
    :dpl => lambda { fetch @compile_stack.last },
    
    :car => lambda {|arg| fetch "#{arg}.first" },
    :cdr => lambda {|arg| fetch "#{arg}.drop(1)" },
    :len => lambda {|arg| fetch "#{arg}.length" },
    
    :arg => lambda {|*args|
            # ignore it
            },
    :los => lambda {|*args|
              args.reverse.each{|arg| fetch arg}
              nil
            },
    :psh => lambda {|arg|
              arg = "\"#{arg}\"" if arg.class == String
              fetch arg
              nil
            },
    :lea => lambda {|var|
              return "#{var} = #{@compile_stack.pop}" unless @compile_stack.empty?
              nil
            },
    :add => lambda { opcode_operator "+" },
    :sub => lambda { opcode_operator "-" },
    :mul => lambda { opcode_operator "*" },
    :div => lambda { opcode_operator "/" },
    :cal => lambda {|func|
              _method = method func
              if _method && _method.parameters.length > 0
                args = Array.new
                _method.parameters.length.times do
                  args.push @compile_stack.pop
                end
                return "#{func} #{args.join(', ')}"
              else
                return "#{func}"
              end              
            },
    :jmp => lambda {|label| "#{patched_arg label}"},
    :jz =>  lambda {|label| sole_cond_jump " == 0", label },
    :jnz => lambda {|label| sole_cond_jump " != 0", label },
    :jnl => lambda {|label| sole_cond_jump ".nil?", label },
    :jeq => lambda {|label| cond_jump "==", label },
    :jge => lambda {|label| cond_jump ">", label },
    :jlt => lambda {|label| cond_jump "<", label },
    :rec => lambda {
              "#{@entry_point} #{@labels_arg.first.last.length.times.collect{@compile_stack.pop}.reverse.join(', ')}"
            },
    :ret => lambda {
              "return #{@compile_stack.pop unless @compile_stack.empty?}"
            },
    :exi => lambda {
              "exit"
            },
    :inv => lambda {|obj, f|
              begin
                if method(f).parameters.length == 0
                  fetch "#{obj}.#{f}" 
                else
                  args = method(f).parameters.collect{@compile_stack.pop}
                  fetch "#{obj}.#{f} #{args.join(', ')}"
                end
                nil
              rescue Exception => e
                puts "[OPCODES]<inv> currently is not stable in compiling ruby mode.".red
              end
            }
  }
end

# demo for testing
# @x = Asmrb.new do
#     fun :play
#     arg :toy
#     psh :toy
#     cal :puts
    
#     blo :after_print
#     psh :@times
#     jnl :init_timer

#     blo :append
#     inv :@times, :to_s
#     psh "X"
#     add
#     cal :puts

#     blo :count
#     psh :@times    
#     psh 1
#     add
#     lea :@times
#     psh :@times
#     psh 10
#     jeq :final
#     psh "__"
#     rec

#     blo :final
#     psh "__"
#     cal :puts
#     inv :@times, :to_s
#     psh "Final result = "
#     add
#     cal :puts
#     exi

#     blo :init_timer
#     psh 0
#     lea :@times
#     jmp :append
# end

# @x.is_debug = false
# test = @x.to_ruby
# puts test.light_green
# eval test
# play "I'm The Trung, here we go:"

# # applying: argumented  block ( lambda )
# # should be "inline block" technique also, 
# # to improve performance and local variable sharing.
# @f = Asmrb.new do
#   fun :factorial
#   arg :acc, :n
#   los :n, 1
#   jlt :final
  
#   blo :cont
#   arg :acc, :n
#   los :n, :acc
#   mul
#   los :n, 1
#   sub
#   rec 

#   blo :final
#   arg :acc
#   psh :acc
#   cal :puts
#   exi             # no return yet, because return doesn't mean anything inside a block. we can't escape.
# end

# source = @f.to_ruby
# puts source
# eval source
# factorial 1, 3