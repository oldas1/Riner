
#pragma once

#include <src/config/Config.h>
#include <src/compute/DeviceId.h>
#include <src/application/Device.h>
#include <vector>
#include <deque>

namespace miner {

    namespace configUtils {

        Config loadConfig(const std::string &configPath);

        std::vector<std::string> getUniqueAlgoImplNamesForProfile(Config::Profile &prof, const std::vector<DeviceId> &deviceIds);

        std::vector<std::reference_wrapper<const Config::Pool>> getConfigPoolsForPowType(const Config &config,
                                                                                         const std::string &algoType);

        Config::Profile::Mapping getMappingForDevice(Config::Profile &prof, size_t deviceIndex);

        std::vector<std::reference_wrapper<Device>> prepareAssignedDevicesForAlgoImplName(const std::string &implName, const Config &config, Config::Profile &prof, std::deque<optional<Device>> &devicesInUse, const std::vector<DeviceId> &allIds);

    }
}