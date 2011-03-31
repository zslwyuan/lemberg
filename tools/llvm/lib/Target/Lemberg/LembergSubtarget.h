//===- LembergSubtarget.h - Define Subtarget for the Lemberg ---*- C++ -*-====//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file declares the LEMBERG specific subclass of TargetSubtarget.
//
//===----------------------------------------------------------------------===//

#ifndef LEMBERG_SUBTARGET_H
#define LEMBERG_SUBTARGET_H

#include "llvm/Target/TargetSubtarget.h"
#include "llvm/Target/TargetMachine.h"
#include <string>

namespace llvm {

  // TODO: this is a dirty hack that should go away in the future
  namespace LembergFU {
	  enum FuncUnit {
		  SLOT0, SLOT1, SLOT2, SLOT3,
		  ALU0, ALU1, ALU2, ALU3,
		  MEMU, JMPU,
		  FPU_DEC, FPU_EX1, FPU_EX2, FPU_EX3,
		  FPU_EX4, FPU_EX5, FPU_EX6, FPU_EX7,
		  FPU_WB
	  };
  }

  class LembergSubtarget : public TargetSubtarget {
	bool dummy_feature;
    InstrItineraryData InstrItins;
  public:
    LembergSubtarget(const std::string &TT, const std::string &FS);

    /// ParseSubtargetFeatures - Parses features string setting specified
    /// subtarget options.  Definition of function is auto generated by tblgen.
    std::string ParseSubtargetFeatures(const std::string &FS,
                                       const std::string &CPU);

    /// getInstrItins - Return the instruction itineraies based on subtarget
    /// selection.
    const InstrItineraryData &getInstrItins() const { return InstrItins; }

	/// enablePostRAScheduler - We never enable the normal
	/// PostRAScheduler, because we always do the post-RA scheduling
	/// ourselves
	bool enablePostRAScheduler(CodeGenOpt::Level OptLevel,
							   TargetSubtarget::AntiDepBreakMode& Mode,
							   RegClassVector& CriticalPathRCs) const {
		return false;
	}

	// TODO: this is a dirty hack that should go away in the future
    unsigned getFuncUnit(LembergFU::FuncUnit FU) const;
  };

} // end namespace llvm

#endif