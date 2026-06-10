#include "simt_types.h"
#include <fstream>
#include <stdexcept>

namespace simt {

void PerfCounters::write_file(const std::string& path) const {
    std::ofstream f(path);
    if (!f) throw std::runtime_error("Cannot open stats file: " + path);
    f << "cycles="           << cycles           << "\n";
    f << "instructions="     << instructions     << "\n";
    f << "stall_data="       << stall_data       << "\n";
    f << "stall_structural=" << stall_structural << "\n";
    f << "stall_memory="     << stall_memory     << "\n";
    f << "stall_no_warp="    << stall_no_warp    << "\n";
    f << "cycles_issuing="       << cycles_issuing       << "\n";
    f << "wb_count="             << wb_count             << "\n";
    f << "total_diverge_events=" << diverge_events       << "\n";
    f << "masked_thread_cycles=" << masked_thread_cycles << "\n";
}

} // namespace simt
