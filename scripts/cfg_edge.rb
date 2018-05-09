# Codestitcher
# author Rahman Lavaee

class CFGEdge
	include Comparable
	attr_accessor :prob
	attr_reader :from
	attr_reader :to
	attr_reader :type
	attr_accessor :count_map
	attr_reader :prob_val

	def initialize(from,to,prob=nil,type=nil)
		@from = from
		@to = to
		@count_map = Hash.new
		@prob = prob
		@type = type
		@prob_val = nil
	end

	def inc_count (value = 1, from_offset=@from.size, to_offset=0)
		if(!@count_map.include?([from_offset,to_offset]))
			@count_map [ [from_offset, to_offset] ] = [value,0] 
		else
			@count_map [ [from_offset,to_offset] ][0] += value
		end
	end
	
	def inc_misp_count (value = 1, from_offset=@from.size, to_offset=0)
		if(!@count_map.include?([from_offset,to_offset]))
			@count_map [ [from_offset, to_offset] ] = [0,value] 
		else
			@count_map [ [from_offset,to_offset] ][1] += value
		end
	end

	def count
		@count_map.values.inject(0) {|psum,v| v[0]+psum}
	end

	def call_count
		@count_map.each.inject(0) {|psum,((from_offset,to_offset),v)| (to_offset==0)?(v[0]+psum):psum}
	end



	def misp_count
		@count_map.values.inject(0) {|psum,v| v[1]+psum}
	end

	def to_s
		"from:#{@from.uname} to:#{@to.uname} [prob:#{(@prob.nil?)?".":@prob.to_s} , count:#{@count_map.inspect}]"
	end

	def get_prob_val
		if(@prob_val.nil?)
			@prob_val = begin
				if(@from.func!=@to.func)
					@prob.nil?? 0 : @prob
				elsif(prob.nil?)
					1.0/@from.func.bb_succs[from.bbid].length
				else
					@prob
				end
			end
		else
			@prob_val
		end
	end
	
	def pgo_weight
		func_entry_count = @from.func.pgo_entry_count+0.5
		get_prob_val * @from.pgo_count.to_f / @from.func.basic_blocks.first.pgo_count * func_entry_count
	end

	def <=>(other_edge)
		count_cmp = (self.count <=> other_edge.count)
		(count_cmp==0)?(pgo_weight <=> other_edge.pgo_weight):(count_cmp)
	end 

	def total_count
		self.count + self.misp_count
	end

=begin
	def marshal_dump
		[@from, @to, @type, @prob, @count]
	end

	def marshal_load((f,t,ty,p,c))
		@from = f
		@to = t
		@type = ty
		@prob = p
		@count = c
	end
=end

end
