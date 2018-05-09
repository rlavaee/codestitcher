# Codestitcher
# author Rahman Lavaee

require_relative "cfg_edge.rb"

class Succs < Hash

	attr_reader :bb

	def initialize(arg)
		@bb = arg
	end

	def inspect
		succs_strs = Array.new
		each { |k,v| succs_strs << k.to_s+"=>"+v.to_s}
		succs_strs.inspect
	end

	def merge_with(other_succs)
		raise if !(self.class === other_succs)
		#puts "BEFORE MERGE: #{self}"
		other_succs.each do |other,e|
			succ = @bb.func.dso.functions[other.func.name].basic_blocks[other.bbid]
			is_succ = (@bb==e.from)
			(self[succ] = CFGEdge.new((is_succ)?(@bb):(succ),(is_succ)?(succ):(@bb),e.prob,e.type)) if(!has_key?(succ))
			self[succ].count_map.merge(e.count_map) {|k,self_val,other_val| [self_val[0] + other_val[0], self_val[1] + other_val[1]]}
		end
		#puts "AFTER MERGE: #{self}"
	end

end
