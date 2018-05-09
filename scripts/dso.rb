# Codestitcher
# author Rahman Lavaee

require 'json'
require 'set'
require 'graphviz' rescue LoadError

class DSO
	@@dso_count = 0
	@@dso_map = Hash.new
	attr_reader :path
	attr_reader :id
	attr_reader :functions
	attr_accessor :tail_callee
	attr_accessor :func_succs
	attr_accessor :func_preds
	attr_reader :total_count
	attr_accessor :function_ids
	attr_reader :scale
	
	def initialize(arg)
		@path = arg
		@id = if(@@dso_map.has_key?(@path))
						@@dso_map[@path]
					else
						@@dso_map[@path] = @@dso_count
						@@dso_count += 1
						@@dso_map[@path]
					end
		@functions = Array.new
		@function_count = 0
		@function_ids = Hash.new
		@func_succs_names = Hash.new
		@func_succs = Hash.new 
		@func_preds = Hash.new 
		@tail_callee = Hash.new
	
	end

	def get_function_id(fname)
		if(@function_ids.include?(fname))
			@function_ids[fname]
		else
			@function_ids[fname]=@function_count
			@function_count+=1
			@function_ids[fname]
		end
	end

  def set_landing_pads
		@functions.each {|func| func.set_landing_pads}
	end

	def set_succs(bb, bb_succs_arg, func_succs_arg)
		#puts "set_succs: #{bb.inspect} #{func_succs_arg}"
		@func_succs_names[bb] = Array.new
		func_succs_arg.each { |succ| @func_succs_names[bb] << succ}
		bb.func.set_bb_succs(bb, bb_succs_arg)
	end

	def set_func_succs
			@func_succs_names.each do |bb,succ_func_name_a|
				succ_func_name_a.each do |succ_func_name|
					if(@function_ids.has_key?(succ_func_name))
						to_bb = get_or_add_basic_block([succ_func_name,0])
						@func_preds[to_bb][bb] = @func_succs[bb][to_bb]=CFGEdge.new(bb,to_bb,1) if(!@func_succs[bb].has_key?(to_bb))
						#@func_succs[bb][to_bb].inc_count(bb.count)
						#puts "adding to func_succs[#{bb.inspect}]: #{to_bb.inspect}"
					end
				end
				if(!@tail_callee[bb].nil?)
					if(@function_ids.has_key?(@tail_callee[bb]))
						@tail_callee[bb] = get_or_add_basic_block([@tail_callee[bb],0])
					else
						@tail_callee.delete(bb)
					end
				end
			end

		@func_succs_names.clear
		remove_instance_variable(:@func_succs_names)

	end


	def get_basic_block(sym)
		parts = sym.split("*")
		func_name = parts.first
		return nil if(!@function_ids.has_key?(func_name))
		bid = (parts.length==2)?(parts.last.to_i):0
		@functions[@function_ids[func_name]].basic_blocks[bid]
	end

	def == other
		(self.class === other) && (@path == other.path)
	end

	alias eql? ==

	def hash
		@id.hash
	end

	
	def get_or_add_basic_block(args)
		func_name = args[0]
		@functions[get_function_id(func_name)]=Function.new(self,func_name) if(!@function_ids.has_key?(func_name))
		func = @functions[@function_ids[func_name]]
		bbid = args[1].to_i
		if(func.basic_blocks[bbid].nil?)
	  	bb = func.basic_blocks[bbid] = BasicBlock.new(func,bbid) 
			func.bb_succs[bbid] = Succs.new(bb)
			func.bb_preds[bbid] = Succs.new(bb)
			@func_succs[bb] = Succs.new(bb)
			@func_preds[bb] = Succs.new(bb)
		end
		bb = func.basic_blocks[bbid]

		if(args.length>2)
			bb.func.pgo_entry_count = args[2].to_i if(bbid==0)	
			index = (bbid==0)?(3):(2)
			bb.pgo_count = args[index].to_i
			bb_succs_arg = JSON.parse(args[index+1])
			func_succs_arg = JSON.parse(args[index+2])
			bb.lp = (args[index+3]=="LP")
			bb.addr = args[index+4].to_i(16)
			bb.size = args[index+5].to_i(16)
			set_succs(bb,bb_succs_arg,func_succs_arg)
		end
		bb
	end

	def inspect
		"{\n"+@functions.map{|f| "#{f.inspect}"}.join("\n")+"}\n"
	end

	
	def merge_with(other_dso)
		raise if !(self.class === other_dso)
		raise if(other_dso.path!=@path)
		other_dso.functions.each {|func| @functions[func.id].merge_with(func)}
		
		other_dso.func_succs.each {|bb,func_succs_bb| @func_succs[bb].merge_with(func_succs_bb)}
		other_dso.func_preds.each {|bb,func_preds_bb| @func_preds[bb].merge_with(func_preds_bb)}
	end

	def reset_counts
		@total_count = @functions.inject(0) {|psum_count,func| func.reset_counts+psum_count}
	end

	def to_dot_graph
		#@functions.values.sort_by {|func| func.addr}.each do |func|
		puts "dumping graphs"
		reset_counts
		@functions.sort_by {|func| -func.count}[0..9].each do |root_func|
			next if(!root_func.is_executed?)
			puts "dumping graph for function: #{root_func.name}"
			g = GraphViz.new( :G , :mclimit => 0.5, :layout => :fdp, :splines => :curved, :outputorder => :nodesfirst , :compound => "true")

			mark = {root_func => 0}
			queue = [root_func]
			while(!(func = queue.shift).nil?)
				dist = mark[func]
				next if(dist==1)
				func.basic_blocks.each do |bb|
					@func_succs[bb].each do |succ,e|
						if(e.count!=0 && !mark.include?(succ.func))
							queue << succ.func
							mark[succ.func] = dist+1	
						end
					end

					@func_preds[bb].each do |pred,e|
						if(e.count!=0 && !mark.include?(pred.func))
							queue << pred.func
							mark[pred.func] = dist+1	
						end
					end

				end
			end

			mark.keys.each do |func|
				puts "including in the graph: function: #{func.name}"
				#for adding bounding box make sure we prefix the graph name cluster
				gf = g.add_graph( "cluster.#{func.name}", :label => "#{func.name}", :color => :gray89, :style => :filled, :fontsize => 90)
				#func.basic_blocks.each {|bb| gf.add_nodes(bb.uname , :label => "BB#{bb.bbid}") if(bb.count!=0)}
				func.basic_blocks.each do |bb| 
					bb_color = if(bb.bbid==0) #is entry block
												"green"
										 elsif (func.bb_succs[bb.bbid].empty?) #is return block
												"indianred1"
										else
												"cyan"
										end
					gf.add_nodes(bb.uname , :label => "BB#{bb.bbid}", :shape => :oval, :width => "#{bb.size.to_f/16}", :height => "1", :style => :filled, :fillcolor => bb_color, :color => :blue, :fontsize => 14) if(bb.count!=0)
				end
				func.bb_succs.each { |bb_succs| bb_succs.each {|succ,e| gf.add_edge(e.from.uname,e.to.uname, :color => :darkviolet, :penwidth => "2", :style => :solid, :weight => e.count) if(e.count!=0)}}
			end

			mark.keys.each do |func|
				func.basic_blocks.each do |bb|
					@func_succs[bb].values.each do |e|
						next if(!mark.include?(e.to.func))
						from_gf = g.get_graph("cluster."+e.from.func.name)
						from_node = from_gf.get_node(e.from.uname)
						next if(from_node.nil?)
						to_gf = g.get_graph("cluster."+e.to.func.name)
						next if(to_gf.nil?)

						e.count_map.each do |k,w|
							is_return = (k[1]!=0)
							line_style = (is_return)?(:dotted):(:dashed)
							to_node = (is_return)?(to_gf.get_node(e.to.uname)):(to_gf)
							#puts "#{e.inspect} => #{k.inspect} --> #{w.inspect}"
							next if(to_node.nil?)
							line_color = (is_return)?(:darkgreen):(:black)
							edge = g.add_edges(from_node, to_node, :weight => w[0], :style => line_style, :penwidth => "2", :color => line_color)
						end
					end
				end
			end
			
			#g.output(:dot => "#{@path}.#{root_func.name}.dot" , :path => "/usr/local")
			begin
				g.output(:pdf => "#{@path}.#{root_func.name}.pdf" , :path => "/usr/local")
				#g.output(:ps => "#{@path}.#{root_func.name}.ps" , :path => "/usr/local")
				#g.output(:dot => "#{@path}.#{root_func.name}.dot" , :path => "/usr/local")
				puts "completed dumping graph for #{root_func.name}"
			rescue
				puts "!!!error in dumping graph for #{root_func.name}"
			end

		end
	end

=begin
	def marshal_dump
		[@path, @functions, @func_succs, @func_preds, @tail_callee]
	end

	def marshal_load (ary)
		@path , @functions, @func_succs, @func_preds, @tail_callee = ary
		if(!@functions.nil?)
			@functions.each_value {|func| func.dso = self}
			@functions.rehash
		end
	end
=end

	def compare_dso(other_dso)
		@functions.inject(0) do |pdiff,func| 
				if(!other_dso.function_ids.has_key?(func.name))
					puts "function is not in other: #{func.name}"
					pdiff + func.basic_blocks.inject(0) {|pp,bb| bb.size + pp}
				else
					other_func = other_dso.functions[other_dso.function_ids[func.name]]
					pdiff + func.compare_func(other_func)
				end
		end
	end

	def self.load_agg_profile(exe_file_path)
		dump_file_path = exe_file_path+".profile.agg.dump"
		if File.exists?(dump_file_path+".gz")
			system("gunzip -c #{dump_file_path}.gz > #{dump_file_path}")
			puts "LOADING.....#{exe_file_path}"
			return File.open(dump_file_path,"r") {|df| Marshal.load(df)}
		else
			#puts "dump does not exist"
			nil
		end
	end


	def dump_to_file
		puts "DUMPING.....#{@path}"
		dump_file_path = @path+".profile.agg.dump"
		File.open(dump_file_path,"w") { |df| Marshal.dump(self,df)}
		`gzip -f #{dump_file_path}`
		puts "DUMPING.....END"
	end

	def self.load_from_symbols(exe_file_path)
		new_dso = DSO.new(exe_file_path)
		puts "reading exe syms for: #{exe_file_path}"
		IO.popen("llvm-nm --numeric-sort --print-size #{exe_file_path}","r") do |nm_pipe|
			nm_pipe.each_line do |line|
				tokens = line.chomp.gsub(/\s+/m,' ').strip.split(" ")
				tokens[-1] = tokens[-1].strip
				if(tokens.length>=4)
					bb_args = tokens.last.split(/[*-]/)
					if(bb_args.length>1)
						bb_args << "NOLP" if(bb_args.last!="LP")
						bb_args << tokens[0] << tokens[1]
						new_dso.get_or_add_basic_block(bb_args)
					end
				end
			end
			new_dso.set_func_succs
			new_dso.set_landing_pads
		end
		puts "reading exe syms completed"
		new_dso
	end



end


