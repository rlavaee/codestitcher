# Codestitcher
# author Rahman Lavaee

require 'set'

FIXNUM_MAX = (2**(0.size * 8 -2) -1)

class MaxPathCover

  attr_reader :path_cover
  attr_reader :weight
  attr_reader :path_cover_edges

  def initialize(func)
    @func = func
    @n = @func.basic_blocks.length
    @path_cover = Array.new
    @weight = 0
    @max_weight = 0
    @matched_to_upper = Array.new(@n)
    @matched_to_lower = Array.new(@n)

    @out_edge = Array.new(@n,nil)
    @in_edge = Array.new(@n,nil)

    reachable_node_set = Set.new

    @edges = Array.new(@n)
    @inverse_edges = @n.times.map {|_| Array.new}
    @n.times.each do |bbid|
      @edges[bbid] = Array.new
      @func.bb_succs[bbid].each do |_,e|
        if(e.count!=0 && e.to.bbid!=bbid)
          @edges[bbid] << [e.to.bbid,e.count]
          reachable_node_set << e.to.bbid
          reachable_node_set << bbid
          @inverse_edges[e.to.bbid] << [bbid,e.count]
        end
      end
      @edges[bbid].sort_by! {|e| -e[1]}
    end

    #puts @edges.inspect

    @reachable_nodes = reachable_node_set.to_a

    @nodes = @n.times.select {|bbid| !@edges[bbid].empty?}
    @nodes.sort_by! {|bbid| -@edges[bbid].map{|to_bbid,w| w}.max}
    @timeout = 3600.0 * 0.1* @func.total_count / @func.dso.total_count
  end

  def get_max_cycle_cover(nodes_left)
    @weight = 0
    @matched_to_lower = Hash.new
    @matched_to_upper = Hash.new {|h,k| h[k] = [nil,0]}

    loop do
      #find shortest paths
      any_changed = false
      parent = Hash.new
      distance = Hash.new
      last_edge = Hash.new {|h,k| h[k]=0}
      changed = Hash.new {|h,k| h[k]=false}


      nodes_left.each do |from_bbid|
        if(@matched_to_lower[from_bbid].nil?)
          @edges[from_bbid].each do |to_bbid,w|
            next if (!@in_edge[to_bbid].nil?)
            if(distance[to_bbid].nil? || (distance[to_bbid] > -w))
              distance[to_bbid] = -w
              parent[to_bbid] = from_bbid
              last_edge[to_bbid] = -w
              changed[to_bbid] = true
              any_changed = true
            end
          end
        end
      end

      while any_changed
        any_changed = false
        new_changed = Hash.new {|h,k| h[k]=false}
        @reachable_nodes.each do |bbid|
          (matched_bbid,matched_dist) = @matched_to_upper[bbid]
          next if(matched_bbid.nil?)
          next if (!@out_edge[matched_bbid].nil?)
          if(changed[bbid])
            @edges[matched_bbid].each do |to_bbid,w|
              next if(!@in_edge[to_bbid].nil?)
              next if(to_bbid == matched_bbid)
              new_dist = -w + distance[bbid] + matched_dist
              if(distance[to_bbid].nil? || (new_dist < distance[to_bbid]))
                distance[to_bbid] = new_dist
                parent[to_bbid] = matched_bbid
                last_edge[to_bbid] = -w
                new_changed[to_bbid] = true
                any_changed = true
              end
            end
          end
        end
        changed = new_changed
      end


      #augment with shortest path
      closest = nil
      closest_dist = 0
      @reachable_nodes.each do |bbid|
        if(@matched_to_upper[bbid].first.nil? && !distance[bbid].nil? && (closest.nil? || distance[bbid] < closest_dist))
          closest = bbid
          closest_dist = distance[bbid]
        end
      end

      break if(closest.nil? || (closest_dist >= 0))

      bbid = closest
      next_bbid = nil

      #augment path now
      loop do
        next_bbid = @matched_to_lower[parent[bbid]]
        @matched_to_lower[parent[bbid]] = bbid
        @matched_to_upper[bbid] = [parent[bbid],-last_edge[bbid]]
        bbid = next_bbid
        break if(bbid.nil?)
      end

      @weight -= closest_dist
    end

  end

  def build_complete_path_cover
    path_map = Hash.new
    @path_cover_edges = Array.new
    @path_cover.each do |path|
      path.each_with_index do |bbid,ind|
        path_map[bbid] = path
        @path_cover_edges << [path[ind-1],bbid,@edges[path[ind-1]].select {|to,_| to==bbid}.first[1] ] if(ind!=0)
      end
    end
    @n.times.each {|bbid| @path_cover << [bbid] if(!path_map.include?(bbid))}
    @path_cover_edges.sort_by! {|e| -e[2]}
  end

  def build_path_cover
    #count = 0
    @path_cover = Array.new
    #all_nodes = Set.new
    @reachable_nodes.each do |bbid_u|
      if(@matched_to_upper[bbid_u].first.nil? && @in_edge[bbid_u].nil?)
        @path_cover << Array.new
        bbid_v = bbid_u
        while !(bbid_v.nil? || bbid_v==-1)
          @path_cover.last << bbid_v
          #puts "bad node is #{bbid_v}" if(all_nodes.include?(bbid_v))
          #all_nodes << bbid_v
          bbid_v = (@matched_to_lower[bbid_v] || @out_edge[bbid_v])
        end
        #count += @path_cover.last.length
      end
    end

    #@n.times.each { |bbid_u| puts "BAD node #{bbid_u}: #{@in_edge[bbid_u]} #{@out_edge[@in_edge[bbid_u]]}" if !all_nodes.include?(bbid_u)}
    #raise("paths not adding up #{@n} --- #{count}: #{@path_cover.map {|path| path.join("-")}.join("\n")}") if(count!=@n)
  end


  def get_approx_max_path_cover
    #puts "getting approx max path cover for function: #{@func.to_s}"
    get_max_cycle_cover(@nodes)
    remove_cycles
    build_path_cover
    update_path_cover_greedy(@nodes)
    build_complete_path_cover
  end

  def remove_cycles
    mark = Hash.new

    @reachable_nodes.each do |bbid_v|
      if(mark[bbid_v].nil? && (@in_edge[bbid_v] || @matched_to_upper[bbid_v].first))
        #following the path down bbid_v
        #puts "following the path down #{bbid_v}"
        bbid_u = bbid_v
        color = bbid_u
        min_edge = @matched_to_upper[bbid_v].last
        victim = (@in_edge[bbid_u].nil?)? bbid_u : nil
        while @in_edge[bbid_u] || @matched_to_upper[bbid_u].first
          if(mark[bbid_u].nil?)
            mark[bbid_u] = color
          elsif(mark[bbid_u]==color)
            @matched_to_lower[@matched_to_upper[victim].first] = nil
            @matched_to_upper[victim][0] = nil
            @weight -= min_edge
            break
          else
            #found a path: no action required
            break
          end

          if(@in_edge[bbid_u].nil? && (victim.nil? || (min_edge > @matched_to_upper[bbid_u].last)))
            min_edge = @matched_to_upper[bbid_u].last
            victim = bbid_u
            #puts "found better edge: #{min_edge}"
          end
          bbid_u = (@in_edge[bbid_u] || @matched_to_upper[bbid_u].first)
        end
      end
    end

  end


  def get_greedy_path_cover
    @weight = 0
    @matched_to_upper = Array.new(@n)
    @matched_to_lower = Array.new(@n,nil)

    @n.times.each { |bbid| @matched_to_upper[bbid] = [nil,0]}

    build_path_cover
    update_path_cover_greedy(@nodes)
    build_complete_path_cover
  end


  def update_path_cover_greedy(nodes_left)
    path_map = Hash.new
    @path_cover.each {|path| path.each {|bbid| path_map[bbid] = path}}
    path_sources = Set.new(@path_cover.map {|path| path.first})

=begin
    edges = Array.new
      @func.bb_succs[bbid].each do |_,e|
        edges << e if(e.count!=0)
      end
    end
    edges.sort!.reverse!
=end
    remaining_edges = Array.new
    nodes_left.each do |from_bbid|
      next if(!@out_edge[from_bbid].nil?)
      @edges[from_bbid].each do |to_bbid,w|
        next if (!@in_edge[to_bbid].nil?)
        from_path = path_map[from_bbid]
        to_path = path_map[to_bbid]
        remaining_edges << [from_bbid,to_bbid,w] if(!from_path.equal?(to_path) && from_bbid==from_path.last && to_bbid==to_path.first)
      end
    end

    remaining_edges.sort_by! {|(f,t,w)| -w}

    remaining_edges.each do |from_bbid,to_bbid,w|
      from_path = path_map[from_bbid]
      to_path = path_map[to_bbid]
      if(!from_path.equal?(to_path) && from_bbid==from_path.last && to_bbid==to_path.first)
        to_path.each do |bbid|
          from_path << bbid
          path_map[bbid] = from_path
        end
        path_sources.delete(to_bbid)
        @matched_to_upper[to_bbid] = [from_bbid,w]
        @matched_to_lower[from_bbid] = to_bbid
        @weight += w
      end
    end

    @path_cover = path_sources.map {|s| path_map[s]}
    #puts "total weight is: #{validate_path_cover}"
  end

  def validate_path_cover
    raise "does not match #{@path_cover.flatten.sort.inspect}\n#{@reachable_nodes.sort.inspect}" if (@path_cover.flatten.sort != @reachable_nodes.sort)
    @path_cover.inject(0) do |psum,path|
      _path = Array.new(path)
      from_bbid = _path.shift
      _path.inject(psum) do |ppsum,next_bbid|
        w = @edges[from_bbid].select {|to_bbid,_w| to_bbid == next_bbid}.first[1]
        from_bbid = next_bbid
        ppsum + w
      end
    end
  end

  def get_max_path_cover(lb_weight)
    @max_weight = lb_weight
    
    puts "getting path cover for #{@func}: lower bound is: #{@max_weight}, timeout is: #{@timeout}"

    @start = Time.now
    @timeout_past = false
    
    construct_path_cover(0,@nodes)
    
    if(!@max_out_edge.nil?)
      @path_cover = Array.new
      path_sources = @n.times.select {|bbid| !@max_out_edge[bbid].nil? && @max_in_edge[bbid].nil?}

      total_weight = 0
      path_sources.each do |bbid|
        @path_cover << Array.new
        _bbid = bbid
        while(!_bbid.nil?)
          @path_cover.last << _bbid
          _bbid = @max_out_edge[_bbid]
        end
      end
    
    end
    build_complete_path_cover
    @weight = @max_weight
  end

  def fill_order(bbid, visited, stack, inv_edges)
    visited[bbid] = true
    c = @out_edge[bbid]
    if(!c.nil?)
      if(c!=-1)
        inv_edges[c] << [bbid,@edges[bbid].select {|(to,w)| to == c}.first[1]]
        fill_order(c,visited,stack,inv_edges)  if(!visited[c])
      end
    else
      @edges[bbid].each do |c,w| 
        next if (!@in_edge[c].nil?)
        inv_edges[c] << [bbid,w]
        fill_order(c,visited,stack,inv_edges) if(!visited[c])
      end
    end
    stack << bbid
  end

  def dfs_visit(bbid, color, col, inv_edges)
    color[bbid] = col
    inv_edges[bbid].each {|(c,_)| dfs_visit(c,color,col,inv_edges) if(!color.include?(c))}
  end

  def get_sccs(nodes_left)
    visited = Hash.new {|h,k| h[k] = false}
    stack = Array.new
    inv_edges =  Hash.new {|h,k| h[k] = Array.new}
    _edges = Hash.new {|h,k| h[k] = Array.new}
    @reachable_nodes.each {|bbid| fill_order(bbid, visited, stack, inv_edges) if(!visited[bbid])}

    inv_edges.each {|to_bbid,pred_list| pred_list.each { |(from_bbid,w)| _edges[from_bbid] << [to_bbid,w]}}

    color = Hash.new
    col = -1
    stack.reverse.each {|bbid| dfs_visit(bbid,color,col+=1,inv_edges) if(!color.include?(bbid))}
    #puts color.inspect
    sccs = 0.upto(col).map {|_| Array.new}

    scc_index = Hash.new
    @reachable_nodes.each do |bbid|
      if(!color[bbid].nil?)
        scc_index[bbid] = sccs[color[bbid]].length
        sccs[color[bbid]] << bbid
      end
    end

    max_path = Array.new(sccs.length,nil)

    sccs.each_with_index do |scc,c|
      scc_len = scc.length
      next if(scc_len > 200)
      #puts "scc with size: #{scc_len}"
      max_path[c] = Array.new(scc_len) {Array.new(scc_len) {Array.new(2,0)}}
      scc.each_with_index do |bbid_i,i|
        _edges[bbid_i].each do |(bbid_j,w)|
          next if(color[bbid_j]!=c)
          j = scc_index[bbid_j]
          max_path[c][i][j][0]= (@out_edge[bbid_i] == bbid_j)?(FIXNUM_MAX):(w)
        end
      end
      #puts "finished initialization"
      1.upto(scc_len).each do |k|
        scc.each_with_index do |_,i|
          i_to_k = max_path[c][i][k-1][(k-1)%2]
          scc.each_with_index do |_,j|
            max_path[c][i][j][k%2] =
            if(i_to_k == 0)
              max_path[c][i][j][(k-1)%2]
            elsif((k_to_j = max_path[c][k-1][j][(k-1)%2]) == 0)
              max_path[c][i][j][(k-1)%2]
            else
              new_path = [i_to_k,k_to_j].min
              [max_path[c][i][j][(k-1)%2] , [i_to_k,k_to_j].min].max
            end
          end
        end
      end
      #puts "finished"

    end


    extra_edges = Array.new

    nodes_left.each do |from_bbid|
      next if(!@out_edge[from_bbid].nil?)
      from_edges = _edges[from_bbid].select{|(to,w)| @in_edge[to].nil?}.sort_by {|(to,w)| -w}
      next if(from_edges.empty?)
      (to_bbid,weight) = from_edges.shift
      if(color[to_bbid] == color[from_bbid])
        c = color[to_bbid]
        next if(max_path[c].nil?)
        next if(weight <= max_path[c][scc_index[to_bbid]][scc_index[from_bbid]][sccs[c].length%2])
      end

      other_edge_w = (from_edges.empty?)? 0 : from_edges.first[1]

      other_inv_edges = inv_edges[to_bbid].select {|(from,w)| from!=from_bbid && @out_edge[from].nil?}
      other_inv_edge_w = (other_inv_edges.empty?)? 0 : other_inv_edges.max{|(from,w)| w}[1]
      next if(other_inv_edge_w + other_edge_w > weight)

      extra_edges << [from_bbid,to_bbid,weight]
      #puts "adding edge: #{[from_bbid,to_bbid,weight].inspect} => #{color[from_bbid]} #{color[to_bbid]}"
      @out_edge[from_bbid] = to_bbid
      @in_edge[to_bbid] = from_bbid
    end

    extra_edges
  end

  def clean_edges(total_extra_edges)
    total_extra_edges.each do |(from,to,w)|
      @out_edge[from] = nil
      @in_edge[to] = nil
    end
  end

  def construct_path_cover(_weight,nodes_left)
    total_extra_edges = Array.new
    new_weight = _weight
    nodes_left_set = Set.new(nodes_left)
    #puts "scc began"
    loop do
      #puts "scc round"
      extra_edges = get_sccs(nodes_left_set)
      break if(extra_edges.empty?)
      extra_edges.each do |(from_bbid,to_bbid,w)|
        nodes_left_set.delete(from_bbid)
        total_extra_edges << [from_bbid,to_bbid,w]
        new_weight += w
      end
      #puts "*********************************"
      #puts "left nodes are: #{nodes_left.inspect}"
      #puts "extra edges are #{extra_edges.inspect}"
      #puts "*********************************"
    end

    #puts "sccs finished"

    new_nodes_left = nodes_left_set.to_a



    if (Time.now - @start > @timeout)
      @timeout_past = true
      puts "TIMEOUT"
      return
    end

    if(new_nodes_left.empty?)
      if( new_weight > @max_weight)
        @max_out_edge = @out_edge.map {|bbid| (bbid==-1)?(nil):(bbid)}
        @max_in_edge = Array.new(@in_edge)
        puts "better weight: #{ new_weight}"
        @max_weight = new_weight
      end
      clean_edges(total_extra_edges)
      return
    end

    #puts "not null in_edge: #{@in_edge.select{|i| !i.nil?}}"
    upbound = new_nodes_left.inject (new_weight) do |psum,from_bbid|
      good_edges = @edges[from_bbid].select {|(to_bbid,w)| @in_edge[to_bbid].nil?}
      max_edge_w = (good_edges.empty?)? 0 : good_edges.map {|(to_bbid,w)| w}.max
      psum + max_edge_w
    end

    if(upbound <= @max_weight )
      puts "simply bound at #{upbound} at node: #{@nodes.length - new_nodes_left.length} (from #{@nodes.length}) (max_weight: #{@max_weight})"
      clean_edges(total_extra_edges)
      return
    end


    inv_upbound = @reachable_nodes.select{|bbid| @in_edge[bbid].nil?}.inject(new_weight) do |psum,to_bbid|
      good_edges = @inverse_edges[to_bbid].select {|(from_bbid,w)| @out_edge[from_bbid].nil?}
      max_edge_w = (good_edges.empty?)? 0 : good_edges.map {|(from_bbid,w)| w}.max
      psum + max_edge_w
    end

    if(inv_upbound <= @max_weight )
      puts "simply inv_bound at #{inv_upbound} at node: #{@nodes.length - new_nodes_left.length} (from #{@nodes.length}) (max_weight: #{@max_weight})"
      clean_edges(total_extra_edges)
      return
    end

    if(@nodes.length - new_nodes_left.length > 15)
      @weight = 0
      get_max_cycle_cover(new_nodes_left)

      if(new_weight + @weight <= @max_weight)
        puts "bound at #{new_weight+ @weight} at node: #{@nodes.length - new_nodes_left.length} (from #{@nodes.length})"
        clean_edges(total_extra_edges)
        return
      end

      remove_cycles
      build_path_cover
      update_path_cover_greedy(new_nodes_left)

      if( new_weight + @weight > @max_weight )
        @max_out_edge = @out_edge.map {|bbid| (bbid==-1)?(nil):(bbid)}
        @max_in_edge = Array.new(@in_edge)
        puts "better weight with approx: #{new_weight+@weight}"
        @n.times.each do |bbid|
          if(!@matched_to_lower[bbid].nil?)
            @max_out_edge[bbid] = @matched_to_lower[bbid]
            @max_in_edge[@matched_to_lower[bbid]] = bbid
          end
        end
        @max_weight = new_weight + @weight
      end
    end

=begin
    if(@node_begin > 15)
      get_greedy_path_cover

      if(extra_weight + _weight + @weight > @max_weight)
          @max_out_edge = @out_edge.map {|bbid| (bbid==-1)?(nil):(bbid)}
          @max_in_edge = Array.new(@in_edge)
          puts "better weight with greedy: #{@total_extra_weight + _weight+@weight}"
          @n.times.each do |bbid|
            if(!@matched_to_lower[bbid].nil?)
              @max_out_edge[bbid] = @matched_to_lower[bbid]
              @max_in_edge[@matched_to_lower[bbid]] = bbid
            end
          end
          @max_weight = @total_extra_weight + _weight + @weight
      end
    end
=end


    bbid = new_nodes_left.shift

    @out_edge[bbid] = -1
    construct_path_cover(new_weight,new_nodes_left)
    @out_edge[bbid] = nil


    @edges[bbid].each do |to_bbid,w|
      next if(!@in_edge[to_bbid].nil?)
      tail = to_bbid
      tail = @out_edge[tail] while !(@out_edge[tail].nil? || @out_edge[tail]==-1)
      next if(tail==bbid) #loop
      @out_edge[bbid] = to_bbid
      @in_edge[to_bbid] = bbid
      construct_path_cover(new_weight+w,new_nodes_left)
      @out_edge[bbid] = nil
      @in_edge[to_bbid] = nil
    end

    clean_edges(total_extra_edges)

  end

end
