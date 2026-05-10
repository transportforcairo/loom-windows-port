// WIN32 PATCH R6: _tz->_tz (Windows time.h macro clash)
// WIN32 PATCH: timezone->tz
// Copyright 2016, University of Freiburg,
// Chair of Algorithms and Data Structures.
// Authors: Patrick Brosi <brosi@informatik.uni-freiburg.de>

#ifndef AD_CPPGTFS_GTFS_AGENCY_H_
#define AD_CPPGTFS_GTFS_AGENCY_H_

// WIN32 PATCH: 	imezone is a global in MinGW's time.h; undef it
#ifdef _WIN32
#ifdef timezone
#undef timezone
#endif
#endif
#include <string>
#include "flat/Agency.h"

using std::exception;
using std::string;

namespace ad {
namespace cppgtfs {
namespace gtfs {

class Agency {
 public:
  typedef Agency* Ref;
  static std::string getId(Ref r) { return r->getId(); }

  Agency() {}

  Agency(const std::string& id, const std::string& name, const std::string& url,
         const std::string& tz_ /* WIN32: was timezone */, const std::string& lang,
         const std::string& phone, const std::string& fare_url,
         const std::string& agency_email)
      : _id(id),
        _name(name),
        _url(url),
        _tz(tz_),
        _lang(lang),
        _phone(phone),
        _fare_url(fare_url),
        _agency_email(agency_email) {}

  Agency(const char* id, const char* name, const char* url,
         const char* tz_ /* WIN32: was timezone */, const char* lang, const char* phone,
         const char* fare_url, const char* agency_email)
      : _id(id),
        _name(name),
        _url(url),
        _tz(tz_),
        _lang(lang),
        _phone(phone),
        _fare_url(fare_url),
        _agency_email(agency_email) {}

  const std::string& getId() const { return _id; }

  const std::string& getName() const { return _name; }

  const std::string& getUrl() const { return _url; }

  const std::string& getTimezone() const { return _tz; }

  const std::string& getLang() const { return _lang; }

  const std::string& getPhone() const { return _phone; }

  const std::string& getFareUrl() const { return _fare_url; }

  const std::string& getAgencyEmail() const { return _agency_email; }

  flat::Agency getFlat() const {
    flat::Agency r;
    r.id = _id;
    r.name = _name;
    r.url = _url;
    r.timezone = _tz;
    r.lang = _lang;
    r.phone = _phone;
    r.fare_url = _fare_url;
    r.agency_email = _agency_email;
    return r;
  }

  // TODO(patrick): implement setters

 private:
  std::string _id, _name, _url, _tz, _lang, _phone, _fare_url,
      _agency_email;
};

}  // namespace gtfs
}  // namespace cppgtfs
}  // namespace ad

#endif  // AD_CPPGTFS_GTFS_AGENCY_H_
