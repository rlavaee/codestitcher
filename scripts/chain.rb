# Codestitcher
# author Rahman Lavaee

class BBNode
  attr_accessor :prev_node
  attr_accessor :next_node
  attr_accessor :chain
  attr_reader :bb
  attr_accessor :addr

  def initialize(chain,bb)
    @bb = bb
    bb.node = self
    @addr = 0
    @prev_node = nil
    @next_node = nil
    @chain = chain
  end

  def hash
    self.object_id.hash
  end

  alias eql? ==

  def == other
    self.object_id == other.object_id
  end

end

class BBChain
    attr_reader :total_count
    attr_reader :total_misp_count
    attr_reader :total_size
    attr_reader :head
    attr_reader :tail

    def initialize(bb)
      @head = @tail = BBNode.new(self,bb)
      @total_count = bb.count
      @total_misp_count = bb.misp_count
      @total_size = bb.size
    end

    def concat(chain)
      #puts "merging #{self.inspect} with #{chain.inspect}"
      if(chain.instance_of?(BBChain))
        @total_count += chain.total_count
        @total_misp_count += chain.total_misp_count
        chain.each { |bb_node| bb_node.addr += @total_size; bb_node.chain = self}
        @total_size += chain.total_size
        @tail.next_node = chain.head
        chain.head.prev_node = @tail
        @tail = chain.tail
      else
        raise "attempting to add non-chain to chain #{chain}"
      end
      self
    end

    def each
      node = @head
      while !node.nil?
        yield node
        node = node.next_node
      end
    end

    def reverse_each
      node = @tail
      while !node.nil?
        yield node
        node = node.prev_node
      end
    end

    def map(&block)
      result = []
      each do |node|
        result << block.call(node)
      end
      result
    end

    def hash
      self.object_id.hash
    # @head.bb.hash
    end

    def exec_density
      (@total_size==0)? (0) :(@total_count.to_f / @total_size)
    end

    alias eql? ==

    def == other
      self.object_id == other.object_id
      #(self.class === other) &&  (@head.bb == other.head.bb)
    end

    def inspect
      "CHAIN{ count:#{@total_count}, size:#{@total_size} representative: "+@head.bb.to_s + "}-->#{self.object_id}"
    end


  def <=> other_chain
    @head.bb <=> other_chain.head.bb
  end

  def all_total_count
    @total_count + @total_misp_count
  end

end


class ChainList < Array
  attr_reader :total_count
  attr_reader :total_size
  attr_reader :rep

  def initialize(c)
    push(c)
    @total_count = c.total_count
    @total_size = c.total_size
    @rep = c
  end

  def merge cl,merge_points
    self.reverse! if merge_points[0]!=self.last
    cl.reverse! if merge_points[1]!=cl.first
    self << cl
  end

  def << cl
      if(cl.instance_of?(ChainList))
        @total_count += cl.total_count
        @total_size += cl.total_size
        cl.each { |chain| push(chain)}
      else
        raise "attempting to add non-chain list to chain list #{cl}"
      end
      self
  end

  def exec_density
    (@total_size==0)? (0) :(@total_count.to_f / @total_size)
  end

  alias eql? ==

  def == other
    (self.class === other) && (@rep == other.rep)
  end


  def hash
    @rep.hash
  end

  def to_s
    "CHAIN{ rep: #{@rep.inspect}"
  end

  def inspect
    "CHAIN{ count:#{@total_count}, size:#{@total_size} representative: "+@rep.inspect + "}"
  end

  def <=> other_cl
    @rep <=> other_cl.rep
  end

  def end_points
    [first,last]
  end
end

class ChainListEdge
  attr_accessor :count
  attr_reader :cl1
  attr_reader :cl2

  def initialize(cl1,cl2,do_sort=false)
    if(do_sort)
      sorted = [cl1,cl2].minmax
      @cl1 = sorted[0]
      @cl2 = sorted[1]
    else
      @cl1 = cl1
      @cl2 = cl2
    end
    @count = 0
  end

  def <=> other_edge
    @count <=> other_edge.count
  end

  def to_s
    "["+cl1.to_s+","+cl2.to_s+"]: #{@count}"
  end
end


class ChainEdge
  attr_accessor :counts
  attr_accessor :chains

  def initialize(_chains, do_sort=false)
    @chains = Array.new((do_sort)?(_chains.sort {|x,y| x<=>y}):(_chains))
    reset_counts
  end

  def total_count
    @counts.inject(0) {|count,psum| psum+count}
  end

  def == other
    (self.class === other) && (@chains == other.chains)
  end

  alias eql? ==

  def <=> other_edge
    total_count <=> other_edge.total_count
  end

  def inspect
    @chains.inspect+  "-->" + @counts.inspect
  end

  def reset_counts
    @counts = Array.new((@chains.length*(@chains.length-1)/2), 0)
  end
end


class CSChainEdge < ChainEdge

  def initialize(_chains, do_sort=false)
    super(_chains, do_sort)
  end

  def weight
    #@counts.inject(0) {|psum,count| psum+count}.to_f / @chains.inject(0) {|psum,c| psum+c.total_size}
    @counts.each_with_index.inject(0) do |psum,(count,i)|
      psum + count.to_f / case i
      when 0
        1+@chains[0].total_size + @chains[1].total_size
      when 1
        1+@chains[1].total_size + @chains[2].total_size
      when 2
        1+@chains[0].total_size + @chains[1].total_size + @chains[2].total_size
      when 3
        1+@chains[2].total_size + @chains[3].total_size
      when 4
        1+@chains[1].total_size + @chains[2].total_size + @chains[3].total_size
      when 5
        1+@chains[0].total_size + @chains[1].total_size + @chains[2].total_size + @chains[3].total_size
      end
    end
  end


  def <=> other_edge
    self.weight <=> other_edge.weight
  end

  def inspect
    super + " , --->weight---> "+ self.weight.to_s
  end

end
