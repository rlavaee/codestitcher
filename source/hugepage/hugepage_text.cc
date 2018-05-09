// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Author: Ken Chen <kenchen@google.com>
//
// hugepage text library to remap process executable segment with hugepages.
// Modified by: Rahman Lavaee <rlavaee@cs.rochester.edu>

#include <link.h>
#include <unistd.h>
#include <sys/mman.h>
#include "bit_cast.h"
#include <cstddef>
#include <iostream>
#include <cassert>
#include <set>
#ifndef MAP_HUGETLB
#define MAP_HUGETLB 0x40000
#endif
#ifndef TMPFS_MAGIC
#define TMPFS_MAGIC 0x01021994
#endif
#ifndef MADV_HUGEPAGE
#define MADV_HUGEPAGE 14
#endif
const int kHpageShift = 21;
const int kHpageSize = (1 << kHpageShift);
const int kHpageMask = (~(kHpageSize - 1));
const int kProtection = (PROT_READ | PROT_WRITE);
const int kMremapFlags = (MREMAP_MAYMOVE | MREMAP_FIXED);
// The number of hugepages we want to use to map chrome text section
// to hugepages. With the help of AutoFDO, the hot functions are grouped
// in to a small area of the binary.
const int kNumHugePages = 4;

std::set<std::string> remapped_set;

// Get an anonymous mapping backed by explicit transparent hugepage
// Return NULL if such mapping can not be established.

static void* GetTransparentHugepageMapping(const size_t hsize) {
	//std::cerr << "Getting transparent huge page mapping of size: " << hsize << "\n";
	// setup explicit transparent hugepage segment
	char* addr = static_cast<char*>(mmap(NULL, hsize + kHpageSize, kProtection,
				MAP_ANONYMOUS | MAP_PRIVATE, -1, 0));
	if (addr == MAP_FAILED) {
		std::cerr << "unable to mmap anon pages, fall back to small page\n";
		return NULL;
	}
	// remove unaligned head and tail regions
	size_t head_gap = kHpageSize - (size_t)addr % kHpageSize;
	size_t tail_gap = kHpageSize - head_gap;
	munmap(addr, head_gap);
	munmap(addr + head_gap + hsize, tail_gap);
	void* haddr = addr + head_gap;
	if (madvise(haddr, hsize, MADV_HUGEPAGE)) {
		std::cerr << "no transparent hugepage support, fall back to small page\n";
		munmap(haddr, hsize);
		return NULL;
	}
	return haddr;
}
// memcpy for word-aligned data which is not instrumented by AddressSanitizer.
static void NoAsanAlignedMemcpy(void* dst, void* src, size_t size) {
	assert(0U == size % sizeof(uintptr_t));  // size is a multiple of word size.
	assert(0U == reinterpret_cast<uintptr_t>(dst) % sizeof(uintptr_t));
	assert(0U == reinterpret_cast<uintptr_t>(src) % sizeof(uintptr_t));
	uintptr_t* d = reinterpret_cast<uintptr_t*>(dst);
	uintptr_t* s = reinterpret_cast<uintptr_t*>(src);
	for (size_t i = 0; i < size / sizeof(uintptr_t); i++)
		d[i] = s[i];
	//for (int i = size/sizeof(uintptr_t)-1; i>=0; i--)
}
// Remaps text segment at address "vaddr" to hugepage backed mapping via mremap
// syscall.  The virtual address does not change.  When this call returns, the
// backing physical memory will be changed from small page to hugetlb page.
//
// Inputs: vaddr, the starting virtual address to remap to hugepage
//         hsize, size of the memory segment to remap in bytes
// Return: none
// Effect: physical backing page changed from small page to hugepage. If there
//         are error condition, the remapping operation is aborted.
static int MremapHugetlbText(void* vaddr, const size_t hsize) {
	assert(0ul == (reinterpret_cast<uintptr_t>(vaddr) & ~kHpageMask));
	void* haddr = GetTransparentHugepageMapping(hsize);
	if (haddr == NULL)
		return -1;
	// Copy text segment to hugepage mapping. We are using a non-asan memcpy,
	// otherwise it would be flagged as a bunch of out of bounds reads.
 
	NoAsanAlignedMemcpy(haddr, vaddr, hsize);
	//fprintf(stderr,"doing the remap from vaddr: %p\t and size: %xu\t to haddr: %p\n",vaddr, hsize,haddr);
	// change mapping protection to read only now that it has done the copy
	if (mprotect(haddr, hsize, PROT_READ | PROT_EXEC)) {
		std::cerr << "can not change protection to r-x, fall back to small page\n";
		munmap(haddr, hsize);
		return -1;
	}
	// remap hugepage text on top of existing small page mapping
	if (mremap(haddr, hsize, hsize, kMremapFlags, vaddr) == MAP_FAILED) {
		std::cerr << "unable to mremap hugepage mapping, fall back to small page\n";
		munmap(haddr, hsize);
		return -1;
	}
	return 0;
	//fprintf(stderr,"remapped code size: 0x%x\n",hsize);
}


// Top level text remapping function.
//
// Inputs: vaddr, the starting virtual address to remap to hugepage
//         segsize, size of the memory segment to remap in bytes
// Return: none
// Effect: physical backing page changed from small page to hugepage. If there
//         are error condition, the remaping operation is aborted.
extern void RemapHugetlbText(void* vaddr, const size_t segsize, void* text_end) {
	// remove unaligned head regions
	uintptr_t head_gap =  
		(kHpageSize - reinterpret_cast<uintptr_t>(vaddr) % kHpageSize) %
		kHpageSize;
  //fprintf(stderr,"head gap is %x, text size: %x\n",head_gap,segsize);
	uintptr_t addr = reinterpret_cast<uintptr_t>(vaddr) + head_gap;
	if (segsize < head_gap)
		return;
	size_t hsize = segsize - head_gap;
	size_t hsize_div = hsize & kHpageMask;
	size_t hsize_mod = hsize - hsize_div;
	size_t huge_code_size = hsize_div;
	if(hsize_mod >= 0x80000 && reinterpret_cast<uintptr_t>(text_end) >= reinterpret_cast<uintptr_t>(vaddr)+hsize_div+kHpageSize)
		huge_code_size += kHpageSize;
	
	
	//fprintf(stderr,"hsize is %x, text end is %x, vaddr is %x\n",huge_code_size, text_end, vaddr);
/*
	if (hsize > kHpageSize * kNumHugePages)
		hsize = kHpageSize * kNumHugePages;
*/
	if (huge_code_size == 0)
		return;
	if(MremapHugetlbText(reinterpret_cast<void*>(addr), huge_code_size)==-1)
		std::cerr << "BAD COULDN'T MAP TO HUGE PAGES\n";
	//else
	//	std::cerr << "MAPPED TO HUGE PAGES\n";
}

extern "C" void RemapToHugePages(uint8_t * hot_text_begin, uint8_t * hot_text_end, uint8_t * text_begin, uint8_t * text_end){
	//fprintf(stderr,"%p %p\n",reinterpret_cast<uintptr_t>(hot_text_begin), reinterpret_cast<uintptr_t>(hot_text_end));
	const char * use_huge_page = getenv("USE_HUGE_PAGE");
	//const char * exit_after_remap = getenv("EXIT_AFTER_REMAP");
	//const char * exit_before_remap = getenv("EXIT_BEFORE_REMAP");
	assert(use_huge_page!=NULL && "USE_HUGE_PAGE is not set!");
	//assert(exit_after_remap!=NULL && "EXIT_AFTER_REMAP is not set!");
	//assert(exit_before_remap!=NULL && "EXIT_BEFORE_REMAP is not set!");
	if(strcmp(use_huge_page,"OFF")==0)
		return;
	else if(strcmp(use_huge_page,"ON")!=0){
		fprintf(stderr,"invalid value for USE_HUGE_PAGE\n");
		exit(-1);
	}

	//if(strcmp(exit_before_remap,"ON")==0)
	//	exit(0);

	size_t text_size = reinterpret_cast<uintptr_t>(hot_text_end) - reinterpret_cast<uintptr_t>(hot_text_begin);	
	//size_t text_size = reinterpret_cast<uintptr_t>(text_end) - reinterpret_cast<uintptr_t>(text_begin);	
/*
	size_t mod = text_size & 0x1FFFFF;
	text_size -= mod;
	uintptr_t aligned_hot_text_end = reinterpret_cast<uintptr_t>(hot_text_end) - mod + (2<<20);
	if(mod >= 0x10000 &&  (reinterpret_cast<uintptr_t>(text_end) > aligned_hot_text_end))
		text_size += (2<<20);
*/

	RemapHugetlbText(hot_text_begin, text_size,text_end);
	//RemapHugetlbText(text_begin, text_size, text_end);

	//if(strcmp(exit_after_remap,"ON")==0)
	//	exit(0);
}

// For a given ELF program header descriptor, iterates over all segments within
// it and find the first segment that has PT_LOAD and is executable, call
// RemapHugetlbText().
//
// Inputs: info: pointer to a struct dl_phdr_info that describes the DSO.
//         size: size of the above structure (not used in this function).
//         data: user param (not used in this function).
// Return: always return true.  The value is propagated by dl_iterate_phdr().
static int FilterElfHeader(struct dl_phdr_info* info, size_t size, void* data) {
	std::string obj_str(info->dlpi_name);
	if(remapped_set.count(obj_str))
		return 0;
	else
		remapped_set.insert(obj_str);

	void* vaddr;
	int segsize;
	/*
	printf("0x%8.8x %-30.30s 0x%8.8x %d %d %d %d 0x%8.8x\n",
			info->dlpi_addr, info->dlpi_name, info->dlpi_phdr, info->dlpi_phnum,
			info->dlpi_adds, info->dlpi_subs, info->dlpi_tls_modid,
			info->dlpi_tls_data);
			*/
	for (int i = 0; i < info->dlpi_phnum; i++) {
		//fprintf(stderr,"\t\t header %2d: address=%10p\t , dlpi_addr: %10p\n", i, (void *) (info->dlpi_addr + info->dlpi_phdr[i].p_vaddr), (void*) (info->dlpi_addr));
		if (info->dlpi_phdr[i].p_type == PT_LOAD &&
				info->dlpi_phdr[i].p_flags == (PF_R | PF_X)) {
			vaddr = bit_cast<void*>(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
			segsize = info->dlpi_phdr[i].p_filesz;
			if(segsize > kHpageSize)
				RemapHugetlbText(vaddr, segsize,0);
			
			// Only re-map the first text segment.
			break;
		}
	}
	return 0;
}

void * thread_proc(void *){
	sleep(10);
	dl_iterate_phdr(FilterElfHeader, 0);
	return NULL;
}

// Main library function.  This function will iterate all ELF segments and
// attempt to remap text segment from small page to hugepage.
// If remapping is successful.  All error conditions are soft fail such that
// effect will be rolled back and remap operation will be aborted.
extern "C" void ReloadElfTextInHugePages(void) {
	//pthread_t t1;
	//int res = pthread_create(&t1,NULL, thread_proc, NULL);
	dl_iterate_phdr(FilterElfHeader, 0);
}
