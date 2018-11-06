#pragma once

#include <src/common/WorkCommon.h>
#include <src/common/Pointers.h>
#include <src/common/Optional.h>
#include <src/common/Assert.h>
#include <src/pool/Work.h>
#include <string>

namespace miner {
    class WorkResultBase;
    class WorkBase;
    template<AlgoEnum A> class WorkResult;
    template<AlgoEnum A> class Work;

    struct PoolConstructionArgs {
        //don't confuse this with Config::Pool. PoolConstructionArgs may be used
        //to pass refs to other subsystems in the future (e.g. io_service)
        std::string host;
        std::string port;
        std::string username;
        std::string password;
    };

    class WorkProvider {
    protected:
        virtual optional<unique_ptr<WorkBase>> tryGetWork() = 0;
        virtual void submitWork(unique_ptr<WorkResultBase> result) = 0;

        virtual uint64_t getPoolUid() const = 0; //call may be redirected to individual pools of a pool switcher

        static uint64_t createNewPoolUid();

    public:

        //returns either nullopt or a valid unique_ptr (!= nullptr)
        template<AlgoEnum A>
        optional<unique_ptr<Work<A>>> tryGetWork() {
            auto maybeWork = tryGetWork();
            if (maybeWork) {
                auto &work = maybeWork.value();
                MI_EXPECTS(work != nullptr && work->getAlgoEnum() == A);
                return static_unique_ptr_cast<Work<A>>(std::move(maybeWork.value()));
            }
            return nullopt;
        }

        template<AlgoEnum A>
        void submitWork(unique_ptr<WorkResult<A>> result) {
            MI_EXPECTS(result != nullptr && result->getAlgoEnum() == A);

            submitWork(static_unique_ptr_cast<WorkResultBase>(std::move(result)));
        }

        virtual ~WorkProvider() = default;
    };

}