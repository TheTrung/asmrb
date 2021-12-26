asmrb
=======

I. Intro

Asmrb is my intend over making a high-level assembly language.
Which shorten your horizonal source, better flow and readability.

And to solve my question about how recursion loop through assembly
by just jumping from label to label. 

Have fun !
    
Just a prototype, play around if you know Ruby. 
Get the Gem: https://rubygems.org/gems/asmrb

II. Install

\* asmrb is at very early state of experiment,
  so all required gems would be pretty light-weight
  and just for debugging and colorful printing.

    gem install asmrb

III. Usage

Let's create one as below:

    a = Asmrb.new do
      fun :rec_print    # define a function, also label to jump.
      arg arr           # arguments
      psh 0
      len arr           # get length of arr as array
      jge :print           # then jump to :print block
      ret                  # else, jump to :exit block
      blo :print        # start of :print
      car arr           # get out first element of arr
      cal :puts         # call ruby's puts
      cdr arr           # get rest of arr Array to @stack
      rec               # jump back to :rec_print ( or start of this _fntion )
    end

toggle the debug mode to see steps:

    a.is_debug = true

invoke it with right arugument type:

    a.invoke [1, 2]

convert it to ruby code:

    a.to_ruby

Asmrb can run "infinite recursion" without being overflow, 
by storing value with its own stack. 

    Look at "rake test" for more samples.

\* Execute source file:

To execute a source file like `demo.arb`:

    asmrb demo.arb

VI. Features

* I actually created asmrb to see how it change the coding style
while still remain all high-level ruby functions. There're early
plans on making LLVM underhood to improve overall performance,
or just compiling down to ruby for maximum compatiability and
go on with all ruby implementations.

\* currently implemented:

    Note: to see all implemented operators, run:
    Asmrb.new.all_ops

\* operations:

all ops follow the rule:

    psh 2
    psh 1
    add     # push (1 + 2) to stack


to remove top-most element off stack:

    psh 1
    pop    

same to above, when pushed values:

    sub     # 1 - 2
    add     # 1 + 2
    mul     # 1 * 2
    div     # 1 / 2
    icr a   #  a = a + 1
    dcr a   #  a = a - 1
    dpl     # duplicate top-most value on stack

\* array:

    car arr  # get first element of array
    cdr arr  # get rest element of array
    len arr  # get length of array
    los arr  # load all array elements on stack
    los :a   # load all elements in :a variable

\* jump:

    blo :name   # create a label/block
    
    jlt   :label  # jump if  a < b 
    jge   :label  # jump if  a > b 
    jeq   :label  # jump if  a = b 
    jnz   :label  # jump if not zero
    jmp   :label  # jump to certain labeled immediately
    jnl   :label  # jump if nil

\* function define:

    fun :function  # define function name and also a label to jump.
    arg a,b   # function parameters binded to a and b.
    req 3     # function require 3 arguments.
    rec       # to recursively call function again.
    lea :a    # load top-most value to variable a     

\* high-level:

    mov 1, :a    # there is still this, but it will soon be removed.
    
    
    red :+       # reduce current stack frame by :+ operator
    map :o       # map as usual to current stack
    cal :puts    # calling ruby function
    
    inv :a, :f   # invoke function "f" of object "a" with n "args"
    
    dbg          # debug by pry at local instruction
    ret          # exit and return top-most stack value
    exi          # force exit
