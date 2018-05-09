require_relative "cfg_edge.rb"

class BasicBlock
	attr_accessor :func
	attr_reader :bbid
	attr_accessor :size
	attr_accessor :count
	attr_accessor :addr
	attr_accessor :node
  	attr_accessor :lp
	attr_accessor :misp_count
	attr_accessor :pgo_count
	
	def layout_string
		str = @func.name+"*"+@bbid.to_s+":"+@count.to_i.to_s
		str += "+"
		str += (@func.bb_succs[@bbid].empty?)? ("."):(@func.bb_succs[@bbid].map{|succ,e| succ.bbid.to_s+":"+e.count.to_i.to_s}.join("#"))
		str += "+";
		preds = @func.dso.func_preds[self].select {|pred,e| e.call_count!=0}.map {|pred,e| pred.func.name+"*"+pred.bbid.to_s+":"+e.call_count.to_i.to_s}
		str += (preds.empty?)?("."):(preds.join("#"))
		str += "+"
		str += @size.to_s
		str += "+"
		str += @lp ? "LP" : "NOLP"
	end

	def get_next
		bb_succs = @func.bb_succs[@bbid]
		case bb_succs.length
		when 0
			_tail_callee = @func.dso.tail_callee[self]
			return _tail_callee
		when 1
			return bb_succs.keys.first
		when 2
			bb_succs.each {|succ,e| return succ if(e.type=="F")}
			return nil
		else
			return nil
		end
	end

	def get_next_direct
		bb_succs = @func.bb_succs[@bbid]
		case bb_succs.length
		when 0
			return @func.dso.tail_callee[self]
		when 1
			return bb_succs.keys.first
		else
			return nil
		end
	end

	
	def initialize(func,bbid)
		@func = func
		@bbid = bbid
		@size = nil	
		@addr = nil
		@count = 0
		@node = nil
		@lp = false
	end

	def inc_bb_succ(to_bb,from_offset,to_offset,mispredict,count=1)
		bb_succs = @func.bb_succs[@bbid]
		if(to_offset==0 && bb_succs.has_key?(to_bb))
			bb_succs[to_bb].inc_count(count)
			if(mispredict=="M")
				misp_succs = bb_succs.select {|succ,e| e.type=="F"}
				misp_succs.first[1].inc_misp_count(count)  if(!misp_succs.empty?)
			end
		else
			func_preds = @func.dso.func_preds[to_bb]
			func_succs = @func.dso.func_succs[self]
			func_preds[self] = func_succs[to_bb] = CFGEdge.new(self,to_bb,0) if (!func_succs.has_key?(to_bb))
			func_succs[to_bb].inc_count(count,from_offset,to_offset)
			to_bb.func.count += count if(to_bb.bbid==0)
		end
		to_bb.func.count = count if(to_bb.func.count < count)
	end

	def bb_pred_misp_sum 
		@func.bb_preds[@bbid].inject(0) {|psum,(pred,e)| psum+e.misp_count}
	end

	def func_pred_misp_sum
		@func.dso.func_preds[self].inject(0) {|psum,(pred,e)| psum+e.misp_count}
	end

	def bb_succ_sum 
		@func.bb_succs[@bbid].inject(0) {|psum,(succ,e)| psum+e.count}
	end

	def bb_pred_sum 
		@func.bb_preds[@bbid].inject(0) {|psum,(pred,e)| psum+e.count}
	end

	def func_pred_sum
		@func.dso.func_preds[self].inject(0) {|psum,(pred,e)| psum+e.count}
	end

	def func_succ_max 
		@func.dso.func_succs[self].inject(0) {|pmax,(succ,e)| [pmax,e.count].max}
	end
	

	def reset_count
		@misp_count = 0#func_pred_misp_sum + bb_pred_misp_sum
		@count = [func_succ_max,bb_succ_sum,bb_pred_sum,func_pred_sum].max
		@count = [@count, @func.count].max if(@bbid==0)
		@func.bb_succs[@bbid].each {|_,e| e.count_map[[@size,0]] = [0,0] if(e.count_map.empty?)}
		@func.bb_succs[@bbid].each {|succ_bbid,e| e.count_map.each {|_,v| v[0] = @count}} if(@func.bb_succs[@bbid].length==1)
		@func.bb_succs[@bbid].each {|succ_bbid,e| e.count_map.each {|_,v| v[0] = @count}} if(@func.bb_succs[@bbid].length==1)
		@count
	end

	def inspect
		to_s
	end

	def hash
		@func.hash ^ @bbid.hash
	end

	def uname
		@func.name+":"+@bbid.to_s
	end


	def == other
		#(self.class === other) && (@uname == other.uname)
		(self.class === other) && !@func.nil? && (@func == other.func) && (@bbid == other.bbid)
	end

	alias eql? ==


	def to_s
		uname+"&&"+@lp.to_s+"("+@count.to_s+")"
		#@func.dso.path+":"+uname
	end

	def <=> other_bb
		uname <=> other_bb.uname
	end

	def total_count
		@count + @misp_count
	end


=begin
	def marshal_dump
		[@bbid, @size]
	end

	def marshal_load(ary)
		@bbid , @size = ary
	end
=end


end
