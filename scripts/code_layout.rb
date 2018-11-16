# Codestitcher
# author Rahman Lavaee

require_relative 'chain.rb'
require_relative 'heap.rb'
require_relative 'max_path_cover.rb'
require_relative 'linked_list.rb'
require_relative 'cfg_edge.rb'

#DIST_LIMITS = [16,64,2 << 10, 4 << 10, 32 << 10, 128 << 10, 256 << 10, 512 << 10, 2 << 20 ]
DIST_LIMITS = [16 , 64 , 4 << 10 , 256 << 10 ,2 << 20 ]



class CodeLayout
  def initialize(_profiles,_do_affinity)
    @profiles = _profiles
    @profiles.each {|dso_path,prof_dso| prof_dso.reset_counts}
    @all_chains_ALL = Hash.new {|h,k| h[k] = Set.new}
    @hot_chain_map_ALL = Hash.new {|h,k| h[k] = Hash.new}
    @cold_chain_map_ALL = Hash.new {|h,k| h[k] = Hash.new}
    @cold_funcs_ALL = Hash.new {|h,k| h[k] = Array.new}
    @all_chain_lists_ALL = Hash.new {|h,k| h[k] = Set.new}
    @chain_list_map_ALL = Hash.new {|h,k| h[k] = Hash.new}
    @in_edges_ALL = Hash.new {|h,k| h[k] = Hash.new}
    @affinity_succs = Hash.new
    @do_affinity = _do_affinity
    @reorders_bbs = true
  end


  def reset_dso(dso_path)
    @dso = @profiles[dso_path]
    @all_chains = @all_chains_ALL[dso_path]
    @hot_chain_map = @hot_chain_map_ALL[dso_path]
    @cold_chain_map = @cold_chain_map_ALL[dso_path]
    @cold_funcs = @cold_funcs_ALL[dso_path]
    @all_chain_lists = @all_chain_lists_ALL[dso_path]
    @chain_list_map = @chain_list_map_ALL[dso_path]
    @in_edges = @in_edges_ALL[dso_path]
  end

  def is_bb?
    @reorders_bbs
  end

  def sequence_functions
    @dso.functions.each do |func|
      if(!func.is_executed?)
        @cold_funcs << func
      else
        init_bb_chains(func)
        func.basic_blocks.each_with_index do |bb,bbid|
          join_bb_chains_if_possible(bb,func.basic_blocks[bbid+1]) if(bbid < func.basic_blocks.length-1)
        end
        coalesce_hot_cold(func)
        add_chain_lists(func)
      end
    end

  end


  def split_functions
    @dso.functions.each do |func|
      if(!func.is_executed?)
        @cold_funcs << func
      else
        init_bb_chains(func)
        if(func.are_bbs_executed?)
          chain_bbs(func,false)
          coalesce_landing_pads(func)
          chain_bbs(func,true)
          join_all_chains(func,false)
          join_all_chains(func,true)
        else
          func.basic_blocks.each_with_index do |bb,bbid|
            join_bb_chains_if_possible(bb,func.basic_blocks[bbid+1]) if(bbid < func.basic_blocks.length-1)
          end
        end
        coalesce_hot_cold(func)
        add_chain_lists(func)
      end
    end
  end

  def coalesce_landing_pads(func)
    return if(!func.is_executed?)
    return if(func.landing_pads.nil?)
    if(!func.landing_pads.empty?)
      first_lp = func.basic_blocks[func.landing_pads.first]
      func.landing_pads[1..-1].each do |lp_bbid|
        join_bb_chains(first_lp,func.basic_blocks[lp_bbid])
      end
    end
  end

  def init_bb_chains(func)
    func.basic_blocks.each {|bb| (@all_chains << BBChain.new(bb)) if(!bb.nil?)}
  end

  def chain_tail_calls
    @best_tail_caller = Hash.new
    @all_chains.each do |chain|
      is_caller_executed = chain.total_count!=0
      tail_callee = @dso.tail_callee[chain.tail.bb]
      next if(tail_callee.nil?)
      is_callee_executed  = !tail_callee.node.nil? && tail_callee.node.chain.total_count!=0
      next if !is_callee_executed || !is_caller_executed
      if(!@best_tail_caller.include?(tail_callee))
        @best_tail_caller[tail_callee] = chain.tail.bb
      else
        cur_best_caller = @best_tail_caller[tail_callee]
        cur_tail_edge = @dso.func_succs[cur_best_caller][tail_callee]
        this_tail_edge = @dso.func_succs[chain.tail.bb][tail_callee]
        @best_tail_caller[tail_callee] = chain.tail.bb if(cur_tail_edge < this_tail_edge)
      end
    end
    @best_tail_caller.each do |callee_bb,caller_bb|
      join_bb_chains_if_possible(caller_bb,callee_bb)
    end
  end

  def chain_path_cover(func,path_cover_edges)
    w = 0
    path_cover_edges.each do |from,to,_w|
      #puts "#{from} #{to}: #{_w}"
      join_bb_chains_if_possible(func.basic_blocks[from],func.basic_blocks[to])
      w += _w
    end
    #path_cover.each do |path|
    # path.each_with_index do |bbid,i|
    #   if(i!=0)
    #     raise "could not join #{path[i-1]} to #{path[i]} error" if(!join_bb_chains_if_possible(func.basic_blocks[path[i-1]],func.basic_blocks[path[i]]))
    #     w += func.bb_succs[path[i-1]][func.basic_blocks[path[i]]].count
    #   end
    # end
    #end
    w
  end

  def chain_bbs(func,spec,max_size=nil)
    all_edges = func.basic_blocks.inject([]) do |result,bb|
      (bb.nil?)?(result):(result + func.bb_succs[bb.bbid].values.reject{|e| (spec)?(false):(e.count==0)})
    end
    all_edges.sort_by! {|e| (spec)?(-e.pgo_weight):(-e.count)}
    all_edges.each {|edge| join_bb_chains_if_possible(edge.from,edge.to,max_size)}
  end

  def join_bb_chains_if_possible(from_bb,to_bb,max_size=nil)
    return false if(from_bb.node.nil? || to_bb.node.nil?)
    from_chain = from_bb.node.chain
    to_chain = to_bb.node.chain
    return false if(from_chain.tail.bb!=from_bb || to_chain.head.bb!=to_bb || from_chain==to_chain)
    return false if(!max_size.nil? && (from_chain.total_count!=0 || to_chain.total_count!=0) && (from_chain.total_size + to_chain.total_size > max_size))
    from_chain.concat(to_chain)
    @all_chains.delete(to_chain)
    return true
  end

  def join_all_chains(func,spec)
    all_edges = func.basic_blocks.inject([]) do |result,bb|
      (bb.nil?)?(result):(result + func.bb_succs[bb.bbid].values.reject{|e| (spec)?(false):(e.count==0)})
    end
    all_edges.reject! {|e| (e.from.node.chain.total_count==0 && e.to.node.chain.total_count!=0) || (e.from.node.chain.total_count!=0 && e.to.node.chain.total_count==0)} if(spec)
    all_edges.sort_by! {|e| (spec)?(-e.pgo_weight):(-e.count)}
    all_edges.each {|edge| join_bb_chains(edge.from,edge.to) }
  end

  def coalesce_hot_cold(func)
    hot_cold_chains = func.basic_blocks.inject({"hot"=>Set.new,"cold"=>Set.new}) do |result,bb|
        chain = bb.node.chain
        if(chain.total_count==0.0)
          result["cold"] << chain if(!result["cold"].include?(chain))
        else
          result["hot"] << chain if(!result["hot"].include?(chain))
        end
      result
    end
    #puts "HOT-COLD #{@name}: "+hot_cold_chains.inspect

    hot_cold_chains.each do |hc,chain_set|
      if(!chain_set.empty?)
        chain_a = chain_set.to_a
        top_chain = chain_a.shift
        top_chain = chain_a.inject(top_chain) do |res,chain|
          res.concat(chain)
          @all_chains.delete(chain)
          res
        end
        (hc=="hot" || !func.are_bbs_executed?)?(@hot_chain_map[func] = top_chain):(@cold_chain_map[func] = top_chain)
      end
    end
    #puts @hot_chain_map[func].head.bb.uname if(!@hot_chain_map[func].nil?)
    #puts @cold_chain_map[func].head.bb.uname if(!@cold_chain_map[func].nil?)
  end

  def add_chain_lists(func)
    if(@hot_chain_map.include?(func))
      hc = @hot_chain_map[func]
      @all_chain_lists << @chain_list_map[hc] = ChainList.new(hc)
    end

    if(@cold_chain_map.include?(func))
      cc = @cold_chain_map[func]
      @all_chain_lists << @chain_list_map[cc] = ChainList.new(cc)
    end
  end

  def join_bb_chains(from_bb,to_bb)
    from_chain = from_bb.node.chain
    to_chain = to_bb.node.chain
    if(from_chain!=to_chain)
      from_chain.concat(to_chain)
      @all_chains.delete(to_chain)
    end
  end

  def set_func_in_edges(func)
    @in_edges[func] = @in_edges[func].group_by {|pred_bb,v| pred_bb.func}.map{|f,edges| [f,edges.inject(0.0) {|psum,(pred_bb,v)| psum+v}]}.sort_by {|f,c| c}.reverse
    @in_edges[func].reject! {|f,c| (c < func.affinity_count.to_f * @affinity_threshold)} if(!@affinity_threshold.nil?)
  end

  def prepare_merge_data
  end

  def merge_all_chains_affinity
    prepare_merge_data
    puts "before merge, chains: #{@all_chain_lists.length}"
    if(@do_affinity)
      (0..5).each do |_affinity_level|
        4.downto(4).map {|i| i.to_f/5}.each do |_affinity_threshold|
          puts "affinity merging level: #{_affinity_level}"
          @affinity_level = _affinity_level
          @affinity_threshold = _affinity_threshold
          merge_all_chains
          puts "chains: #{@all_chain_lists.length}"
        end
      end
    end
    @affinity_level = nil
    @affinity_threshold = nil
    merge_all_chains
    puts "after merge, chains: #{@all_chain_lists.length}"
  end


  def set_bb_in_edges(func)
    if(@affinity_level.nil?)
      func.basic_blocks.each do |bb|
        next if(bb.nil?)
        @dso.func_succs[bb].each do |succ,e|
          e.count_map.each do |k,v|
            @in_edges[succ.func] << [bb,v[0]] if(v[0]!=0 && k[1]==0)
          end
        end
      end
    else
      func.affinity_succs[0..@affinity_level].each do |affinity|
        affinity.each do |succ_bb,e|
          @in_edges[succ_bb.func] << [func.basic_blocks[e.from.bbid],e.count]
        end
      end
    end
  end


  def get_orig_call_dist_hist(returns)
    call_dist_hist = (DIST_LIMITS+[nil]).map {|d| [d,0]}.to_h
    affinity_dist_hists = 7.times.map{|i| (DIST_LIMITS+[nil]).map {|d| [d,0]}.to_h}
    @dso.functions.each do |func|
      func.bb_succs.each do |_bb_succs|
        _bb_succs.each do |succ,e|
          e.count_map.each do |k,v|
            next if(k[1]!=0 && !returns)
            from_addr = e.from.addr + k[0]
            to_addr = e.to.addr + k[1]
            dist = (to_addr - from_addr).abs
            upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
            #puts "BB: #{e.to_s}"
            call_dist_hist[upper_bound] += v[0]
          end
        end
      end
    end

    @dso.func_succs.each do |bb,_func_succs|
      _func_succs.each do |succ,e|
        e.count_map.each do |k,v|
            next if(k[1]!=0 && !returns)
            from_addr = e.from.addr + k[0]
            to_addr = e.to.addr + k[1]
            dist = (to_addr - from_addr).abs
            upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
            #puts "FUNC: #{e.to_s}"
            call_dist_hist[upper_bound] += v[0]
          end
      end
    end

    @dso.functions.each do |func|
      func.affinity_succs.each_with_index do |affinity,level|
        #puts "level: #{level}, affinity length: #{affinity.length}"
        affinity.each do |bb,e|
          from_addr = e.from.addr
          to_addr = e.to.addr
          dist = (to_addr - from_addr).abs
          upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
          (level..6).each {|hlevel| affinity_dist_hists[hlevel][upper_bound] += e.count}
        end
      end
    end
    [call_dist_hist,affinity_dist_hists]
  end

  def get_call_dist_hist(returns=true)
    @chain_addr = Hash.new
    @layout.inject(0) {|psum,chain| @chain_addr[chain] = psum; psum+chain.total_size}

    call_dist_hist = (DIST_LIMITS+[nil]).map {|d| [d,0]}.to_h
    affinity_dist_hists = 7.times.map{ |i| (DIST_LIMITS+[nil]).map {|d| [d,0]}.to_h}
    @layout.each do |chain|
      c_addr = @chain_addr[chain]
      chain.each do |bb_node|
        bb = bb_node.bb
        bb_addr = c_addr+bb_node.addr

        bb.func.bb_succs[bb.bbid].each do |succ,e|
          if(!succ.node.nil?)
            e.count_map.each do |k,v|
              next if(k[1]!=0 && !returns)
              from_addr = bb_addr + k[0]
              to_addr = @chain_addr[succ.node.chain] + succ.node.addr + k[1]
              dist = (to_addr - from_addr).abs
              upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
              #puts e.inspect+" ---> "+dist.to_s if(dist >= 4096)
              call_dist_hist[upper_bound] += v[0]
            end
          end
        end

        @dso.func_succs[bb].each do |succ,e|
          if(!succ.node.nil?)
            e.count_map.each do |k,v|
              next if(k[1]!=0 && !returns)
              from_addr = bb_addr + k[0]
              to_addr = @chain_addr[succ.node.chain] + succ.node.addr + k[1]
              dist = (to_addr - from_addr).abs
              upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
              #puts e.inspect+" ---> "+dist.to_s if(dist >= 4096)
              call_dist_hist[upper_bound]+=v[0]
            end
          end
        end

        if(bb.bbid==0)
          bb.func.affinity_succs.each_with_index do |affinity,level|
            affinity.each do |to_bb,e|
              from_addr = bb_addr
              if(!to_bb.node.nil?)
                to_addr = @chain_addr[to_bb.node.chain] + to_bb.node.addr
                dist = (to_addr - from_addr).abs
                upper_bound=DIST_LIMITS.bsearch {|x| x >= dist}
                (level..6).each {|hlevel| affinity_dist_hists[hlevel][upper_bound] += e.count}
              end
            end
          end
        end


      end
    end
    [call_dist_hist,affinity_dist_hists]
  end

  def print_layout
    returns_types = [false]
    returns_types.each do |returns|
      puts "RETURNS:#{returns}"
      puts "ORIGINAL"
      orig_dist_hists = get_orig_call_dist_hist(returns)
      begin
        total = orig_dist_hists[0].inject(0) {|psum,(k,v)| psum + v}
        puts "CALLS: #{orig_dist_hists[0].map {|k,v| "#{k} => #{v.to_s}(#{(v.to_f / total * 100).round(1)}%)"}.join(" , ")}"
      end
      total = orig_dist_hists[0].inject(0) {|psum,(k,v)| psum + v}
=begin
      orig_dist_hists[1].each_with_index do |affinity_dist_hist,level|
        puts "AFFINTIY LEVEL: #{level}"
        total = affinity_dist_hist.inject(0) {|psum,(k,v)| psum + v}
        puts "HIST: #{affinity_dist_hist.map {|k,v| "#{k} => #{v.to_s}(#{(v.to_f / total * 100).round(1)}%)"}.join(" , ")}"
      end
=end
      puts "OPTIMIZED"
      opt_dist_hists = get_call_dist_hist(returns)
      begin
        total = opt_dist_hists[0].inject(0) {|psum,(k,v)| psum + v}
        puts "CALLS: #{opt_dist_hists[0].map {|k,v| "#{k} => #{v.to_s}(#{(v.to_f / total * 100).round(1)}%)"}.join(" , ")}"
      end

=begin
      opt_dist_hists[1].each_with_index do |affinity_dist_hist,level|
        puts "AFFINTIY LEVEL: #{level}"
        total = affinity_dist_hist.inject(0) {|psum,(k,v)| psum + v}
        puts "HIST: #{affinity_dist_hist.map {|k,v| "#{k} => #{v.to_s}(#{(v.to_f / total * 100).round(1)}%)"}.join(" , ")}"
      end
=end
    end

    layout_file_path = @dso.path+".layout.#{@code_layout_tech}"
    #puts "printing layout for #{layout_file_path} => chains: #{@all_chains.length}"
    File.open(layout_file_path,"w") do |lf|
      hot_layout_end = false
      @layout.each do |chain|
        if(!hot_layout_end)
          if(chain.total_count==0)
            hot_layout_end = true
            lf.puts("*hot_layout_end") if(is_bb?)
          end
        #else
          #raise "hot chain after hot_layout_end" if(chain.total_count!=0)
        end
        chain.each do |bb_node|
          if(is_bb?)
            lf.puts(bb_node.bb.layout_string)
          else
            lf.puts ".text.stitch.hot.#{bb_node.bb.func.name}" if(bb_node.bb.bbid==0)
          end
          #lf.puts(bb.func.name+"*"+bb.bbid.to_s)#+"# "+bb.count.to_s+"# ")
        end
      end
      lf.puts "*cold_functions" if(is_bb?)
      @cold_funcs.each {|func| lf.puts func.name if(is_bb?)}
    end
  end

end



class CallChainCluster < CodeLayout
  def initialize(_profiles,_do_affinity)
    super
    @code_layout_tech = @do_affinity?"c3a":"c3"
  end

  def compute_layout
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(dso_path)
        split_functions
        merge_all_chains_affinity
        @layout = @all_chain_lists.sort_by{|chain_list| chain_list.exec_density}.reverse.flatten(1)
        print_layout
      end
    end
  end

  def prepare_merge_data
    @dso.functions.each {|func| @in_edges[func] = Array.new}
  end


  def get_best_pred_func(func)
    (@in_edges[func].empty?)? nil : @in_edges[func].first.first
  end


  def merge_all_chains
    @dso.functions.each {|func| @in_edges[func].clear}

    @dso.functions.each {|func| set_bb_in_edges(func)}
    @dso.functions.each {|func| set_func_in_edges(func)}

    sorted_funcs = @dso.functions.reject {|func| !@hot_chain_map.include?(func)}.sort_by {|func| @hot_chain_map[func].total_count}.reverse

    sorted_funcs.each do |func|
      chain_list = @chain_list_map[@hot_chain_map[func]]
      next if(chain_list.total_size > 4096)
      pred_func = get_best_pred_func(func)
      if(!pred_func.nil?)
        pred_chain_list = @chain_list_map[@hot_chain_map[pred_func]]
        if(!pred_chain_list.nil?  && pred_chain_list!=chain_list && pred_chain_list.total_size <=4096)
          pred_chain_list << chain_list
          chain_list.each {|chain| @chain_list_map[chain]=pred_chain_list}
          #puts "deleting chain_list: #{chain_list.inspect}"
          @all_chain_lists.delete(chain_list)
        end
      end
    end
    sorted_funcs.each do |func|
      func.basic_blocks.each do |bb|
        raise "Could not find #{bb} in layout" if(!@all_chain_lists.include?(@chain_list_map[bb.node.chain]))
      end
    end
  end

  
end

class CallChainClusterF < CallChainCluster
  def initialize(_profiles,_do_affinity)
    super
    @code_layout_tech = @do_affinity ? "c3fa" : "c3f"
    @reorders_bbs = false
  end

  def compute_layout
    puts "doing layout"
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(dso_path)
        sequence_functions
        merge_all_chains_affinity
        @layout = @all_chain_lists.sort_by{|chain_list| chain_list.exec_density}.reverse.flatten(1)
        print_layout
      end
    end
  end
end




class PettisHansen < CodeLayout
  def initialize(_profiles,_do_affinity)
    super
    @code_layout_tech = @do_affinity?"pha":"ph"
    @chain_edges_ALL = Hash.new {|h,k| h[k]=Hash.new}
    @chain_list_edges_ALL = Hash.new {|h,k| h[k]=Hash.new}
  end

  def reset_dso(dso_path)
    super
    @chain_edges = @chain_edges_ALL[dso_path]
    @chain_list_edges = @chain_list_edges_ALL[dso_path]
  end


  def compute_layout
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(dso_path)
        split_functions
        merge_all_chains_affinity
        all_hot_lists = @all_chain_lists.select {|cl| cl.total_count!=0.0}.flatten(1)#.sort_by {|cl| cl.exec_density}.reverse.flatten(1)
        all_cold_lists = @all_chain_lists.select {|cl| cl.total_count==0.0}.flatten(1)
        @layout = all_hot_lists + all_cold_lists
        print_layout
      end
    end
  end

  def prepare_merge_data
    @dso.functions.each {|func| @in_edges[func] = Array.new}
    @edge_heap = Heap.new
    @all_chains.each do |chain1| 
      @chain_edges[chain1] = Hash.new{|h,chain2|  n = ChainEdge.new([chain1,chain2],true); @chain_edges[chain2].store(chain1, h[chain2] = n);}
      cl1 = @chain_list_map[chain1] 
      @chain_list_edges[cl1] = Hash.new{|h,cl2|  n= HeapNode.new(ChainListEdge.new(cl1,cl2,true)); @chain_list_edges[cl2].store(cl1, h[cl2] = n); n }
    end
  end

    

  def merge_all_chains
    @dso.functions.each {|func| @in_edges[func].clear}

    @dso.functions.each {|func| set_bb_in_edges(func)}
  
    @dso.functions.each {|func| set_func_in_edges(func)}

    @all_chains.each do |chain1| 
      @chain_edges[chain1].each {|k,v|  v.counts[0] = 0}
      cl1 = @chain_list_map[chain1] 
      @chain_list_edges[cl1].each{|k,v| v.data.count = 0}
    end


    @dso.functions.each do |func|
      @in_edges[func].each do |pred_func,c|
        func_chain = @hot_chain_map[func]
        pred_func_chain = @hot_chain_map[pred_func]
        cl1 = @chain_list_map[func_chain]
        cl2 = @chain_list_map[pred_func_chain]
        if((cl1!=cl2))# && (cl1.total_size < 4096) && (cl2.total_size < 4096))
          chain_edge = @chain_edges[func_chain][pred_func_chain]
          chain_edge.counts[0] += c
        end
      end
    end


    @all_chain_lists.each do |cl1|
      cl1.each do |chain1|
        @chain_edges[chain1].each do |chain2,e|
          cl2 = @chain_list_map[chain2]
          if((cl1!=cl2))# && (cl1.total_size < 4096) && (cl2.total_size < 4096))
            cl_edge_node = @chain_list_edges[cl1][cl2]
            cl_edge_node.data.count += e.counts[0]
            @edge_heap.insert(cl_edge_node) if(!cl_edge_node.attached?(@edge_heap))
          end
        end
      end
    end

    while(!@edge_heap.empty?)
      max_edge_node = @edge_heap.pop
      max_edge = max_edge_node.data
      #puts "popped is #{max_edge}"
      #TODO get best direction
      directions = [max_edge.cl1.end_points].inject([]) {|p,x| [max_edge.cl2.end_points].inject(p) {|pp,y| pp << [x,y]}}

      merge_points = directions.max do |dir_l,dir_r| 
        value_l = (@chain_edges[dir_l[0]].include?(dir_l[1]))? (@chain_edges[dir_l[0]][dir_l[1]].counts[0]) : 0.0
        value_r = (@chain_edges[dir_r[0]].include?(dir_r[1]))? (@chain_edges[dir_r[0]][dir_r[1]].counts[0]) : 0.0
        return value_l <=> value_r
      end

      max_edge.cl1.merge(max_edge.cl2,merge_points)
      #puts "max_edge.cl1: #{max_edge.cl1.inspect}"

      @chain_list_edges[max_edge.cl2].each do |cl3,e|
        if(cl3!=max_edge.cl1)
          #if((cl3.total_size < 4096) && (max_edge.cl1.total_size < 4096))
            cl_edge_node = @chain_list_edges[max_edge.cl1][cl3]
            cl_edge_node.data.count += e.data.count
            #puts "inserting (|| fixing up): #{cl_edge_node}"
            (cl_edge_node.attached?(@edge_heap))?(cl_edge_node.fixup):(@edge_heap.insert(cl_edge_node))
            #puts "removing edge: #{e}"
          #end
          @edge_heap.remove(e)
        end
        @chain_list_edges[cl3].delete(max_edge.cl2)
      end
      max_edge.cl2.each {|chain| @chain_list_map[chain]=max_edge.cl1}
      @chain_list_edges.delete(max_edge.cl2)
      @all_chain_lists.delete(max_edge.cl2)
    end
  

  end

end


class PettisHansenF < PettisHansen
  def initialize(_profiles,_do_affinity)
    super
    @code_layout_tech = (@do_affinity)?("phfa"):("phf")
    @chain_edges_ALL = Hash.new {|h,k| h[k]=Hash.new}
    @chain_list_edges_ALL = Hash.new {|h,k| h[k]=Hash.new}
    @reorders_bbs = false
  end


  def compute_layout
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(dso_path)
        sequence_functions
        merge_all_chains_affinity
        chain_lists = @all_chain_lists.to_a.flatten(1)
        all_hot_lists = chain_lists.select {|cl| cl.total_count!=0.0}
        all_cold_lists = chain_lists.select {|cl| cl.total_count==0.0}
        @layout = all_hot_lists + all_cold_lists
        print_layout
      end
    end
  end

end


module Scope
  INTRA_FUNC = 1
  INTER_FUNC = 2
  DYNAMIC = 4
  NO_AFFINITY_DYN_ALL = 7
  NO_AFFINITY_STAT_ALL = 3
  NO_AFFINITY_STAT_INTRA = 1
  AFFINITY = 8
  AFFINITY_DYN = 15
  def self.inter_func?(scope)
    (scope & INTER_FUNC)!=0
  end

  def self.intra_func?(scope)
    (scope & INTRA_FUNC)!=0
  end

  def self.affinity?(scope)
    (scope & AFFINITY)!=0
  end

  def self.dynamic?(scope)
    (scope & DYNAMIC)!=0
  end

  def self.static?(scope)
    !dynamic?(scope)
  end



end

class CodeStitcher < CodeLayout

  def initialize(_profiles, _do_affinity, distance_limits)
    super(_profiles,_do_affinity)
    @code_layout_tech = @do_affinity?"csa":"cs"
    @distance_limits = distance_limits
  end


  def compute_layout
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(dso_path)
        add_chains
        chain_tail_calls

        @distance_limits.each do |distance_limit|
          puts "(DYNAMIC) DISTANCE LIMIT: #{distance_limit}"
          puts "without affinity, chains: #{@all_chains.length}"
          @scope = Scope::NO_AFFINITY_DYN_ALL
          add_bb_edges(distance_limit)
          merge_all_chains(distance_limit)
          if(@do_affinity)
            puts "with affinity, chains: #{@all_chains.length}"
            @scope = Scope::AFFINITY_ALL
            add_bb_edges(distance_limit)
            merge_all_chains(distance_limit)
          end
        end

        @distance_limits.each do |distance_limit|
          puts "(STATIC INTRA_FUNC) DISTANCE LIMIT: #{distance_limit}"
          puts "without affinity, chains: #{@all_chains.length}"
          @scope = Scope::NO_AFFINITY_STAT_INTRA
          add_bb_edges(distance_limit)
          merge_all_chains(distance_limit)
        end

        @dso.functions.each {|func| coalesce_cold(func) if(func.is_executed?)}

        @layout = @all_chains.sort_by{|chain| chain.exec_density}.reverse
        print_layout
      end
    end

  end


  def add_chains
    apc_weight = gpc_weight = mpc_weight = max_weight = 0
    total_weight = 0
    more_weight = 0
    @dso.functions.each_with_index do |func,fi|
      #print "function number: #{fi}: #{func.name}"
      if(!func.is_executed?)
        #puts " ---> is cold"
        @cold_funcs << func
      else
        if(!func.are_bbs_executed?)
          init_bb_chains(func)
          func.basic_blocks.each_with_index do |bb,bbid|
            join_bb_chains_if_possible(bb,func.basic_blocks[bbid+1]) if(bbid < func.basic_blocks.length-1)
          end
        else
          #puts " ---> is hot"
          #puts "getting max path cover for func: #{func.name}, basic blocks: #{func.basic_blocks.length}"
          apc = MaxPathCover.new(func)
          apc.get_approx_max_path_cover
          apc_weight += apc.weight
          gpc = MaxPathCover.new(func)
          gpc.get_greedy_path_cover
          gpc_weight += gpc.weight

          #mpc = MaxPathCover.new(func)
          #lb_weight = [gpc.weight,apc.weight].max
          #mpc.get_max_path_cover(lb_weight)
          #mpc_weight += mpc.weight
          #max_weight += [mpc.weight,gpc.weight,apc.weight].max
          mpc = (gpc.weight > apc.weight) ? (gpc) : (apc) #if (mpc.weight == lb_weight)
          #more_weight += mpc.weight - lb_weight
          #puts "total more weight: #{more_weight}), max weight: #{max_weight}"
          #puts "#{mpc.weight} <----> #{[gpc.weight,apc.weight].min}"

          init_bb_chains(func)
          total_weight += chain_path_cover(func,mpc.path_cover_edges)

          coalesce_landing_pads(func)
          #chain_bbs(func,false)    
          chain_bbs(func,true)
        end
        #func.basic_blocks.each do |bb|
        # puts bb.node.chain.map {|n| n.bb.uname}.join(" ") if(bb.node.chain.head==bb.node)
        #end
      end
    end
    puts "TOTAL WEIGHT: #{total_weight}"
    #puts "mpc_weight: #{mpc_weight}, apc_weight: #{apc_weight}, gpc_weight: #{gpc_weight}, max_weight: #{max_weight}, total_weight: #{total_weight}"
  end

  def coalesce_cold(func)
    cold_chain_set =  func.basic_blocks.inject(Set.new) do |result,bb| 
      chain = bb.node.chain
      result << chain if(!result.include?(chain)) if(chain.total_count==0.0)
      result
    end

    if(!cold_chain_set.empty?)
      chain_a = cold_chain_set.to_a
      top_chain = chain_a.shift
      top_chain = chain_a.inject(top_chain) do |res,chain|
        res.concat(chain)
        @all_chains.delete(chain)
        res
      end
    end
  end



  def add_bb_edges(distance_limit)
    @chain_edges = Hash.new
    @all_chains.each {|chain| @chain_edges[chain] = Hash.new}

    @all_edges_ltr = Hash.new
    @all_edges_rtl = Hash.new

    @all_chains.each do |chain|
        next if(Scope.dynamic?(@scope) && (chain.all_total_count==0))
        chain.each do |bb_node|
          bb_pos = bb_node.addr
          bb = bb_node.bb
          next if(Scope.dynamic?(@scope) && (bb.total_count == 0))

          succs = Hash.new
          preds = Hash.new

          if(Scope.affinity?(@scope))
            succs = succs.merge(@affinity_succs[bb]) if(@affinity_succs.has_key?(bb))
            preds = preds.merge(@affinity_preds[bb]) if(@affinity_preds.has_key?(bb))
          else
            succs = succs.merge(bb.func.bb_succs[bb.bbid]) if(Scope.intra_func?(@scope))
            preds = preds.merge(bb.func.bb_preds[bb.bbid]) if(Scope.intra_func?(@scope))

            succs = succs.merge(@dso.func_succs[bb]) if(Scope.inter_func?(@scope))
            preds = preds.merge(@dso.func_preds[bb]) if(Scope.inter_func?(@scope))
          end

          if(Scope.dynamic?(@scope))
            succs.reject! {|succ_bb,e| e.total_count==0}
            preds.reject! {|pred_bb,e| e.total_count==0}
          end

          @all_edges_ltr[bb] = (chain.total_size - bb_pos > distance_limit)? Hash.new :
          begin
            filtered_succs = succs.reject do |succ_bb,e|
              has_in_range = false

              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                next if(succ_bb.node.nil?)
                from_offset = k[0]
                to_offset = k[1]
                next if(to_offset!=0)
                next if(succ_bb.node.chain.all_total_count==0 && chain.all_total_count!=0)
                next if(succ_bb.node.chain.all_total_count!=0 && chain.all_total_count==0)
                if(succ_bb.node.chain!=chain)
                  distance = chain.total_size - bb_pos + bb.size + succ_bb.node.addr + to_offset - from_offset
                  in_range = distance < distance_limit
                  if(in_range)
                    has_in_range = true
                    w = v[0]+v[1]
                    w *= (distance_limit - distance) if distance_limit.is_page?
                    set_edge(chain,succ_bb.node.chain,w)
                  end
                end
              end
              !has_in_range
            end

            filtered_preds = preds.reject do |pred_bb,e|
              has_in_range = false
              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                next if(pred_bb.node.nil?)
                from_offset = k[0]
                to_offset = k[1]
                next if(to_offset!=0)
                next if(pred_bb.node.chain.all_total_count==0 && chain.all_total_count!=0)
                next if(pred_bb.node.chain.all_total_count!=0 && chain.all_total_count==0)
                if(pred_bb.node.chain!=chain)
                  distance = chain.total_size - bb_pos + bb.size + pred_bb.node.addr + from_offset - to_offset
                  in_range = distance < distance_limit
                  if(in_range)
                    has_in_range = true
                    w = v[0] + v[1]
                    w *= (distance_limit - distance) if distance_limit.is_page?
                    set_edge(chain,pred_bb.node.chain,w)
                  end
                end
              end
              !has_in_range
            end

            filtered_succs.merge(filtered_preds)
          end

          @all_edges_rtl[bb] = (bb_pos > distance_limit)? Hash.new : 
          begin
            filtered_succs = succs.reject do |succ_bb,e|
              has_in_range = false
              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                next if(succ_bb.node.nil?)
                from_offset = k[0]
                to_offset = k[1]
                next if(to_offset!=0)
                next if(succ_bb.node.chain.all_total_count==0 && chain.all_total_count!=0)
                next if(succ_bb.node.chain.all_total_count!=0 && chain.all_total_count==0)
                if(succ_bb.node.chain!=chain)
                  distance = succ_bb.node.chain.total_size - succ_bb.node.addr + bb_pos - to_offset  + from_offset
                  in_range = distance < distance_limit
                  has_in_range = true if(in_range)
                end
              end
              !has_in_range
            end

            filtered_preds = preds.reject do |pred_bb,e|
              has_in_range = false
              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                next if(pred_bb.node.nil?)
                from_offset = k[0]
                to_offset = k[1]
                next if(to_offset!=0)
                next if(pred_bb.node.chain.all_total_count==0 && chain.all_total_count!=0)
                next if(pred_bb.node.chain.all_total_count!=0 && chain.all_total_count==0)
                if(pred_bb.node.chain!=chain)
                  distance = pred_bb.node.chain.total_size - pred_bb.node.addr + bb_pos - from_offset + to_offset
                  in_range = distance < distance_limit
                  has_in_range = true if(in_range)
                end
              end
              !has_in_range
            end
            filtered_succs.merge(filtered_preds)
          end
        end

    end

=begin
    @all_chains.each do |lchain|
      @chain_edges[lchain].values.each do |elm|
        lmchains = elm.data.chains
        next if(lmchains.length!=2)
        next if(lmchains.first!=lchain)
        next if(elm.data.counts[0]==0)
        mchain = lmchains.last
        @chain_edges[mchain].values.each do |emr|
          mrchains = emr.data.chains
          next if(mrchains.length!=2)
          next if(mrchains.first!=mchain)
          next if(emr.data.counts[0]==0)
          rchain = mrchains.last
          next if(rchain==lchain)
          set_triple_chain_edge(lchain,mchain,rchain,elm,emr,distance_limit)  if(@chain_edges[lchain].include?([lchain,rchain]))
        end
      end
    end


    @all_chains.each do |lchain|
      @chain_edges[lchain].values.each do |elm|
        lmchains = elm.data.chains
        next if(lmchains.length!=3)
        next if(lmchains.first!=lchain)
        lmchain = lmchains[1]
        rmchain = lmchains.last
        @chain_edges[lmchain].values.each do |emr|
          mrchains = emr.data.chains
          next if(mrchains.length!=3)
          next if(mrchains.first!=lmchain)
          next if(mrchains[1]!=rmchain)
          rchain = mrchains.last
          next if(rchain==lchain)
          set_quadraple_chain_edge(lchain,lmchain,rmchain,rchain,elm,emr,distance_limit)  #if(@chain_edges[lchain].include?([lchain,rchain]))
        end
      end
    end
=end



    @edge_heap = Heap.new

    @all_chains.each { |lchain| @chain_edges[lchain].each { |chains,e| @edge_heap.insert(e) if(chains.first==lchain)} if(@chain_edges.include?(lchain)) }
  end

  def set_triple_chain_edge(lchain,mchain,rchain,elm,emr,distance_limit)

    mid_distance = mchain.total_size
    return if(mid_distance >= distance_limit)

    ltr_w = 0
    lchain.each do |bb_node|
      bb_pos = bb_node.addr
      bb = bb_node.bb
      next if(!@all_edges_ltr.has_key?(bb))
      @all_edges_ltr[bb].each do |t_bb,e|
        t_chain = t_bb.node.chain
        next if(t_chain!=rchain)
        next if(lchain.all_total_count==0 && rchain.all_total_count!=0)
        next if(lchain.all_total_count!=0 && rchain.all_total_count==0)
        t_bb_pos = t_bb.node.addr
        count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
        count_map.each do |k,v|
          to_offset = k[1]
          next if(to_offset!=0)
          distance = lchain.total_size - bb_pos + t_bb_pos + ((e.from == bb)?(k[1] - k[0]):(k[0] - k[1])) + mid_distance
          if(distance < distance_limit)
            w = v[0] + v[1]
            w *= (distance_limit - distance) if distance_limit.is_page?
            ltr_w += w
          end
        end
      end
    end
    if(ltr_w!=0)
      triple = [lchain,mchain,rchain]
      @chain_edges[lchain][triple] = @chain_edges[mchain][triple] = @chain_edges[rchain][triple] = HeapNode.new(CSChainEdge.new(triple)) if(!@chain_edges[lchain].include?(triple))
      node = @chain_edges[lchain][triple]
      node.data.counts[0] += elm.data.counts[0]
      node.data.counts[1] += emr.data.counts[0]
      node.data.counts[2] += ltr_w
    end
  end

=begin
  def set_quadraple_chain_edge(lchain,lmchain,rmchain,rchain,elm,emr,distance_limit)
    mid_distance = lmchain.total_size + rmchain.total_size
    #return if(mid_distance >= distance_limit)

    ltr_w = 0
    lchain.each do |bb_node|
      bb = bb_node.bb
      bb_pos = bb_node.addr
      @all_edges_ltr[bb].each do |t_bb,e|
        t_chain = t_bb.node.chain
        next if(t_chain!=rchain)
        t_bb_pos = t_bb.node.addr
        count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
        count_map.each do |k,v|
          distance = lchain.total_size - bb_pos + t_bb_pos + ((e.from == bb)?(k[1] - k[0]):(k[0] - k[1])) + mid_distance
          if(distance < distance_limit)
            w = v[0] + v[1]
            w *= (distance_limit - distance) if distance_limit.is_page?
            ltr_w += w  
          end
        end
      end
    end
    #if(ltr_w!=0)
      quadraple = [lchain,lmchain,rmchain,rchain]
      @chain_edges[lchain][quadraple] = @chain_edges[lmchain][quadraple] = @chain_edges[rmchain][quadraple] = @chain_edges[rchain][quadraple] = HeapNode.new(CSChainEdge.new(quadraple)) if(!@chain_edges[lchain].include?(quadraple))
      node = @chain_edges[lchain][quadraple]
      node.data.counts[0] += elm.data.counts[0]
      node.data.counts[1] += elm.data.counts[1]
      node.data.counts[2] += elm.data.counts[2]
      node.data.counts[3] += emr.data.counts[1]
      node.data.counts[4] += emr.data.counts[2]
      node.data.counts[5] += ltr_w
    #end
  end
=end


  def set_edge(lchain,rchain,count)
    pair = [lchain,rchain]
    @chain_edges[lchain][pair] = @chain_edges[rchain][pair] = HeapNode.new(CSChainEdge.new(pair))  if(!@chain_edges[lchain].include?(pair))
    node = @chain_edges[lchain][pair]
    prev = node.data.counts[0]
    node.data.counts[0] += count
    raise "BAD +: #{prev} + #{count} --> #INF" if node.data.counts[0].to_f.infinite?
  end

  def merge_all_chains(distance_limit)
    while(!@edge_heap.empty?)
      max_edge_node = @edge_heap.pop
      max_edge = max_edge_node.data
      next if !max_edge.chains.select {|ch| ch.total_size >= distance_limit}.empty?
      next if max_edge.weight==0.0
      #puts "popped is #{max_edge.chains.length} --> #{max_edge.inspect}"
      _chains = max_edge.chains
      lchain = _chains.first

      _chains[1..-1].each do |next_chain|
        @chain_edges.delete(next_chain).values.each do |node|
          node.data.chains.each do |other_chain|
            next if(other_chain == next_chain)
            @chain_edges[other_chain].delete(node.data.chains)
          end
          @edge_heap.remove(node) if(node.attached?(@edge_heap))
        end
      end

      _chains[1..-1].each do |next_chain|
        lchain.concat(next_chain)
        @all_chains.delete(next_chain)
      end

      affected_edges = @chain_edges[lchain]
      affected_edges.each {|_chains,n| n.data.reset_counts}


      lchain.reverse_each do |bb_node|
        bb = bb_node.bb
        bb_pos = bb_node.addr
        next if(!@all_edges_ltr.has_key?(bb))
        break if (lchain.total_size - bb_pos >= distance_limit)
        @all_edges_ltr[bb].delete_if do |t_bb,e|
            has_in_range = false
            t_chain = t_bb.node.chain
            next if(t_chain.all_total_count==0 && lchain.all_total_count!=0)
            next if(t_chain.all_total_count!=0 && lchain.all_total_count==0)
            if(t_chain != lchain)
              t_bb_pos = t_bb.node.addr
              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                distance = lchain.total_size - bb_pos + t_bb_pos + ((e.from == bb)?(k[1] - k[0]):(k[0] - k[1]))
                in_range = distance < distance_limit
                if(in_range)
                  has_in_range = true
                  w = v[0] + v[1]
                  w *= (distance_limit - distance) if distance_limit.is_page?
                  set_edge(lchain,t_chain,w)
                end
              end
            end
            !has_in_range
        end

      end

      lchain.each do |bb_node|
        bb = bb_node.bb
        bb_pos = bb_node.addr
        next if(!@all_edges_rtl.has_key?(bb))
        break if (bb_pos+ bb.size >= distance_limit)
        @all_edges_rtl[bb].delete_if do |t_bb,e|
            has_in_range = false
            t_chain = t_bb.node.chain
            next if(t_chain.all_total_count==0 && lchain.all_total_count!=0)
            next if(t_chain.all_total_count!=0 && lchain.all_total_count==0)
            if(t_chain != lchain)
              t_bb_pos = t_bb.node.addr
              count_map = (Scope.static?(@scope)) ? ({[e.from.size,0]=>[e.pgo_weight,0]}) : (e.count_map)
              count_map.each do |k,v|
                distance = bb_pos + t_chain.total_size - t_bb_pos  + ((e.from == bb)?(k[0]-k[1]):(k[1]-k[0]))
                in_range = distance < distance_limit
                if(in_range)
                  has_in_range = true
                  w = v[0] + v[1]
                  w *= (distance_limit - distance) if distance_limit.is_page?
                  set_edge(t_chain,lchain, w)
                end
              end
            end
            !has_in_range
        end
      end

=begin
      @chain_edges[lchain].values.each do |n|
        _chains = n.data.chains
        if(_chains.length==3)
          _lchain = _chains[0]
          _mchain = _chains[1]
          _rchain = _chains[2]
          lmchains = [_lchain,_mchain]
          mrchains = [_mchain,_rchain]
          elm = @chain_edges[_lchain][lmchains]
          emr = @chain_edges[_mchain][mrchains]
          next if(elm.data.counts[0]==0 || emr.data.counts[0]==0)
          set_triple_chain_edge(_lchain,_mchain,_rchain,elm,emr,distance_limit)
        end
      end


      @chain_edges[lchain].values.each do |n|
        _chains = n.data.chains
        if(_chains.length==4)
          _lchain = _chains[0]
          _lmchain = _chains[1]
          _rmchain = _chains[2]
          _rchain = _chains[3]
          lmchains = [_lchain,_lmchain,_rmchain]
          rmchains = [_lmchain,_rmchain,_rchain]
          elm = @chain_edges[_lchain][lmchains]
          emr = @chain_edges[_lmchain][rmchains]
          next if(elm.data.counts[0]==0 || emr.data.counts[0]==0)
          set_quadraple_chain_edge(_lchain,_lmchain,_rmchain,_rchain,elm,emr,distance_limit)
        end
      end
=end


      @chain_edges[lchain].values.each do |n|
        if(n.data.total_count==0)
          #puts "OUT OF CHAIN: #{n.data.chain1.inspect}"
          _chains = n.data.chains
          _chains.each do |chain|
            @chain_edges[chain].delete(_chains)
          end
          @edge_heap.remove(n) if(n.attached?(@edge_heap))
        else
          (n.attached?(@edge_heap))?(n.fixup):(@edge_heap.insert(n))
        end         
      end

    end
  end

end

class CodeStitcherSplit < CodeStitcher

  def initialize(_profiles,  _do_affinity, distance_limits)
    super
    @code_layout_tech = @do_affinity ? "cssa" : "css"
  end

  def add_chains
    apc_weight = gpc_weight = mpc_weight = max_weight = 0
    total_weight = 0
    more_weight = 0
    @dso.functions.each do |func|
      if(!func.is_executed?)
        @cold_funcs << func
      else
        apc = MaxPathCover.new(func)
        apc.get_approx_max_path_cover
        apc_weight += apc.weight
        gpc = MaxPathCover.new(func)
        gpc.get_greedy_path_cover
        gpc_weight += gpc.weight

        #mpc = MaxPathCover.new(func)
        #lb_weight = [gpc.weight,apc.weight].max
        #mpc.get_max_path_cover(lb_weight)
        #mpc_weight += mpc.weight
        #max_weight += [mpc.weight,gpc.weight,apc.weight].max
        mpc = (gpc.weight > apc.weight) ? (gpc) : (apc) #if (mpc.weight == lb_weight)
        #more_weight += mpc.weight - lb_weight
        #puts "total more weight: #{more_weight}), max weight: #{max_weight}"

        init_bb_chains(func)
        total_weight += chain_path_cover(func,mpc.path_cover_edges)
        coalesce_landing_pads(func)
        #chain_bbs(func,false)
        chain_bbs(func,true)
      end
    end
    #puts "mpc_weight: #{mpc_weight}, apc_weight: #{apc_weight}, gpc_weight: #{gpc_weight}, max_weight: #{max_weight}, total_weight: #{total_weight}"
  end



  def compute_layout
    @profiles.each do |dso_path,prof_dso|
      if(!prof_dso.nil?)
        reset_dso(profile.prof_dso.path)
        add_chains
        chain_tail_calls
        @distance_limits.reject {|dl| dl > 4096}.each do |distance_limit|
          puts "DISTANCE LIMIT: #{distance_limit}: chains: #{@all_chains.length}"
          @scope = Scope::INTRA_FUNC
          add_bb_edges(distance_limit)
          merge_all_chains(distance_limit)
        end

        @dso.functions.each do |func|
          if(func.is_executed?)
            coalesce_cold(func)
          end
        end

        @distance_limits.each do |distance_limit|
          puts "DISTANCE LIMIT: #{distance_limit}: chains: #{@all_chains.length}"
          @scope = Scope::NO_AFFINITY_DYN_ALL
          add_bb_edges(distance_limit)
        merge_all_chains(distance_limit)
        end

        @layout = @all_chains.sort_by {|chain| -chain.exec_density}
        print_layout
      end
    end
  end

end
