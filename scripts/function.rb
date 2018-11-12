# Codestitcher
# author Rahman Lavaee

class Function
  attr_reader :name
  attr_accessor :dso
  attr_accessor :id
  attr_accessor :count
  attr_reader :basic_blocks

  attr_accessor :bb_succs
  attr_accessor :bb_preds
  attr_reader :total_count
  attr_accessor :landing_pads
  attr_accessor :affinity_succs
  attr_accessor :total_exec_size
  attr_accessor :affinity_count
  attr_accessor :pgo_entry_count

  def initialize(dso,name)
    @dso = dso
    @name = name
    @id = @dso.get_function_id(@name)
    @count = 0
    @basic_blocks = Array.new
    @bb_succs = Array.new
    @bb_preds = Array.new
    @landing_pads = Array.new
    @affinity_succs = 7.times.map {|i| Hash.new}
    @affinity_count = 0
    @pgo_entry_count = 0
  end

  def affinity_count
    (@affinity_count.nil?)?(@affinity_count = 0):(@affinity_count)
  end

  def set_landing_pads
    @basic_blocks.each_with_index do |bb,bbid|
      if(bb.lp)
        @landing_pads << bbid
      end
    end
  end

  def set_bb_succs(bb, bb_succs_arg)
    _bb_succs = @bb_succs[bb.bbid]

    bb_succs_arg.each do |succ,v|
      if(succ.is_int?)
        to_bb = @dso.get_or_add_basic_block([@name,succ])
        e = CFGEdge.new(bb,to_bb,v['prob'],v['type'])
        #e.inc_count((bb.count * v['prob']).round) if(!v['prob'].nil?)
        _bb_succs[to_bb]=e
        @bb_preds[to_bb.bbid][bb]= e
      else
        @dso.tail_callee[bb] = succ
      end
    end
    _bb_succs[_bb_succs.keys.first].prob=1 if(_bb_succs.length==1)

  end

  def reset_counts
    @total_count = @basic_blocks.inject(0) do |psum_count,bb|
      psum_count + ((bb.nil?)? 0 : bb.reset_count)
    end
    @total_exec_size = @basic_blocks.inject(0) {|psum_size,bb| psum_size + ((bb.count==0)? 0 : bb.size)}
  end

  def are_bbs_executed?
    if(@bbs_executed.nil?)
      @bbs_executed = false
      @basic_blocks.each { |bb| return (@bbs_executed = true) if(!bb.nil? && bb.count!=0)}
    end
    @bbs_executed
  end

  def is_executed?
    if(@executed.nil?)
        @executed = false
        return (@executed = true) if(@pgo_entry_count!=0)
        return (@executed = true) if(@affinity_count!=0)
        return (@executed = are_bbs_executed?)
    end
    @executed
  end

  def hash
    @dso.hash ^ @id.hash
  end

  alias eql? ==

  def == other
    (self.class === other) && (@id == other.id) && (@dso.id == other.dso.id)
    #(self.class === other) && !@dso.nil? && (@dso == other.dso) && (@name == other.name)
  end

  def to_s
    @dso.path+":"+@name+"are_bbs_executed("+are_bbs_executed?.to_s+"):is_executed("+is_executed?.to_s+")"
  end

  def inspect
    "[\n" + @basic_blocks.map {|bb| "\t"+bb.inspect}.join("\n") + "\n]"+"\n"+@bb_succs.inspect+"\n"+@bb_preds.inspect
  end

  def merge_with(other_func)
    raise if !(self.class === other_func)
    raise if(@name != other_func.name)
    raise if(@dso.path != other_func.dso.path)
    other_func.bb_succs.each_with_index {|other_bb_succs,i| @bb_succs[i].merge_with(other_bb_succs) if(!@bb_succs[i].nil?)}
    other_func.bb_preds.each_with_index {|other_bb_preds,i| @bb_preds[i].merge_with(other_bb_preds) if(!@bb_preds[i].nil?)}
    @count += other_func.count
  end

  def addr
    @basic_blocks.first.addr
  end

=begin
  def marshal_dump
    [@name, @count, @basic_blocks, @bb_succs, @bb_preds]
  end

  def marshal_load(ary)
    @name, @count, @basic_blocks, @bb_succs, @bb_preds = ary
    @basic_blocks.each {|bb| bb.func = self; bb.uname = bb.func.name+":"+bb.bbid.to_s}
  end
=end

  def compare_func(other_func)
    @basic_blocks.inject(0) do |pdiff,bb| 
      bb_size = bb.nil? ? 0 : bb.size
      other_bb = other_func.basic_blocks[bb.bbid]
      other_bb_size = other_bb.nil? ? 0 : other_bb.size
      puts "#{bb.uname}: #{bb_size} <--> #{other_bb_size}" if(bb_size!=other_bb_size)
      pdiff+ (bb_size - other_bb_size)
    end
  end

end
