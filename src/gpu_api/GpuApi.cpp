#include "GpuApi.h"
#include "AmdgpuApi.h"


namespace miner {

    /**
     * Register all GpuApi implementations here.
     * This is necessary so that the compiler includes the necessary code into a library
     * because only GpuApi is referenced by another compilation unit.
     */
    static const GpuApi::Registry<AmdgpuApi> amdgpuRegistry {"AmdgpuApi"};


    opt::optional<int> GpuApi::getEngineClock() {
        return opt::nullopt;
    }

    opt::optional<int> GpuApi::getMemoryClock() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getVoltage() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getTemperature() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getFanPercent() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getFanRpm() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getPower() {
        return opt::nullopt;
    }
    opt::optional<int> GpuApi::getTdp() {
        return opt::nullopt;
    }

    bool GpuApi::setEngineClock(int freq) {
        return false;
    }

    bool GpuApi::setMemoryClock(int freq) {
        return false;
    }

    bool GpuApi::setVoltage(int voltage) {
        return false;
    }

    bool GpuApi::setFanPercent(int percent) {
        return false;
    }

    bool GpuApi::setTdp(int tdp) {
        return false;
    }

    std::unique_ptr<GpuApi> GpuApi::tryCreate(const CtorArgs &args) {
        for (const auto &api : getApis()) {
            LOG(INFO) << "try to create API instance";
            if (auto instance = api(args)) {
                const auto &settings = args.settings;
                if (settings.power_limit_W)
                    instance->setTdp(*settings.power_limit_W);
                if (settings.core_voltage_mV)
                    instance->setVoltage(*settings.core_voltage_mV);
                if (settings.memory_clock_MHz)
                    instance->setMemoryClock(*settings.memory_clock_MHz);
                if (settings.core_clock_MHz || settings.core_clock_MHz_min)
                    instance->setEngineClock(settings.core_clock_MHz.value_or(settings.core_clock_MHz_min.value_or(0)));
                return instance;
            }
        }
        return std::unique_ptr<GpuApi>();
    }

}