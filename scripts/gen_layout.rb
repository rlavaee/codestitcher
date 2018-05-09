# Codestitcher
# author Rahman Lavaee
require_relative "ruby_util.rb"
require_relative "succ.rb"
require_relative "basic_block.rb"
require_relative "function.rb"
require_relative "dso.rb"
require_relative "profile.rb"
require_relative "code_layout.rb"
require "fileutils"

require "optparse"

script_dir = File.dirname(__FILE__)
PERF_BIN = File.join(script_dir,"..","build","perf","perf")
LLVM_NM_BIN = File.join(script_dir,"..","build","llvm","bin","llvm-nm")

options = Hash.new

options[:distance_list] = [64, 4 << 10, 32 << 10, 128 << 10, 256 << 10, 512 << 10, 2 << 20 ]

OptionParser.new do |opts|
	opts.banner = "Usage: gen_layout.rb [options]"

	opts.on("-l","--[no-]load", "load profile") do |v|
		options[:load] = v
	end

	opts.on("-p","--perf-dir [DIR:FILE]","perf directory") do |v|
		options[:perf] = v
	end

	opts.on("-d","--[no-]dump", "dump profile") do |v|
		options[:dump] = v
	end

	opts.on("-L","--[no-]layout [ALG]", "generate layout") do |v|
		options[:layout] =v
	end

	opts.on("-r","--root [PATH]", "root path of binaries") do |v|
		options[:root] = v
	end

	opts.on("-g","--[no-]graph","emit control flow graph") do |v|
		options[:graph] = v
	end

	opts.on("-D", "--distance-list x,y", Array, "list of distance parameters (for CS layout)") do |distance_list|
		options[:distance_list] = distance_list.map {|d| d.to_i}
	end

	opts.on("-A", "--[no-]affinity","use affinity") do |v|
		options[:affinity] = v
	end

	opts.on("-q","--affinity-perf-dir [DIR:FILE]","affinity perf directory") do |v|
		options[:affinity_perf] = v
	end

	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
    		exit
	end

end.parse!

profiles = Hash.new

def read_perf(perf_path,profiles,exe_root)
	puts "reading profile: #{perf_path}"
	is_gz = `file #{perf_path}`.include?("gzip compressed data")	
	if(is_gz)
		system("gunzip -c #{perf_path} > #{perf_path}.gunz")
		perf_path = perf_path+".gunz"
	end
	IO.popen("#{PERF_BIN} script --no-demangle --fields brstackcf -i #{perf_path}","r") do |perf_script_out|
		prof_dso = nil
		perf_script_out.each do |line|
			if(line.start_with?("dso: "))
				dso_path = line.strip[5..-1]
				#puts dso_path
				#puts exe_root
				prof_dso = if(profiles.include?(dso_path))
						profiles[dso_path]
				 	   elsif(dso_path.start_with?(exe_root))
						profiles[dso_path] = DSO.load_from_symbols(dso_path) 
					   else
						nil
					   end
			elsif(!prof_dso.nil?)
				(from_sym, edges_str) = line.strip.split(/\(|\)/)
				from_bb = prof_dso.get_basic_block(from_sym)
				next if(from_bb.nil?)
				edges_str.split(";").each do |edge_str|
					(to_sym, offset_str, predicted, count) = edge_str.split("#")
					to_bb = prof_dso.get_basic_block(to_sym)
					next if(to_bb.nil?)
					offsets = offset_str.split(/\[|,|\]/)
					offsets.shift
					offsets.map!(&:to_i)
					from_bb.inc_bb_succ(to_bb,offsets[0],offsets[1],predicted,count.to_i)
				end
			end
		end
	end
	FileUtils.rm(perf_path) if(is_gz)
	puts "reading profile completed"
end


if(options.include?(:root))
	exe_root = File.expand_path(options[:root])
	if(options[:load])
		files = File.directory?(exe_root)? Dir.glob(File.join(exe_root,"**/*")) : [File.join(exe_root)]
		files.each do |file|
			file_type_out = `file #{file}`
			if(file_type_out.split(" ")[1]=="ELF")
				exe_path = File.expand_path(file)
				prof_dso = DSO.load_agg_profile(exe_path)
				profiles[exe_path] = prof_dso if(!prof_dso.nil?)
			end
		end
	end

	if(options.include?(:perf))
		perf_files = (File.directory?(options[:perf]))? Dir[File.join(options[:perf],"**/*")] : [options[:perf]]
		puts "PERF FILES ARE: #{perf_files.inspect}"

		perf_files.map{|file| File.expand_path(file)}.each{ |perf_file| read_perf(perf_file,profiles,exe_root) if(!File.directory?(perf_file))}
		profiles.each {|dso_path,prof_dso| prof_dso.reset_counts}
	end

end

profiles.each do |dso_path,prof_dso|
	prof_dso.dump_to_file if(options[:dump])
	prof_dso.to_dot_graph if(options[:graph])
end

if(options.include?(:layout))
	alg = case options[:layout]
	when "C3"
		CallChainCluster.new(profiles,options[:affinity])
	when "C3F"
		CallChainClusterF.new(profiles,options[:affinity])
	when "PH"
		PettisHansen.new(profiles,options[:affinity])
	when "PHF"
		PettisHansenF.new(profiles,options[:affinity])
	when "CS"
		CodeStitcher.new(profiles,options[:affinity],options[:distance_list])
	when "CSS"
		CodeStitcherSplit.new(profiles,options[:affinity],options[:distance_list])
	else
		raise "invalid algorithm: #{options[:layout]}"
	end
	alg.compute_layout
end

