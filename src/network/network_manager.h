//
// network_manager.h
//

#ifndef _bmx_network_manager_h
#define _bmx_network_manager_h

#include "viceoptions.h"

#include <circle/net/netsubsystem.h>
#include <circle/types.h>
#include <wlan/bcm4343.h>
#include <wlan/hostap/wpa_supplicant/wpasupplicant.h>

class CLogger;
class CTask;

namespace bmx {

class NetworkManager {
public:
  NetworkManager(void);
  ~NetworkManager(void);

  bool Initialize(const ViceOptions &options);
  bool IsReady(void) const;
  CNetSubSystem *GetNetSubSystem(void) const;

private:
  void LogAddress(void) const;
  void RunConnectTest(const ViceOptions &options);

private:
  CNetSubSystem *m_net;
  CBcm4343Device *m_wlan;
  CWPASupplicant *m_wpaSupplicant;
  CTask *m_statusTask;
  char m_wlanFirmwarePath[64];
  char m_wpaConfigPath[64];
};

} // namespace bmx

#endif
