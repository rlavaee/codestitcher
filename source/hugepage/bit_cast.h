#include <type_traits>
#include <memory.h>
template <class Dest, class Source>
inline Dest bit_cast(const Source& source) {
	static_assert(sizeof(Dest) == sizeof(Source),
			"bit_cast requires source and destination to be the same size");
	static_assert(std::is_trivially_copyable<Dest>::value,
			"bit_cast requires the destination type to be copyable");
	static_assert(std::is_trivially_copyable<Source>::value,
			"bit_cast requires the source type to be copyable");
	Dest dest;
	memcpy(&dest, &source, sizeof(dest));
	return dest;
}
