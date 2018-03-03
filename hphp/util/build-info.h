/*
   +----------------------------------------------------------------------+
   | HipHop for PHP                                                       |
   +----------------------------------------------------------------------+
   | Copyright (c) 2010-present Facebook, Inc. (http://www.facebook.com)  |
   +----------------------------------------------------------------------+
   | This source file is subject to version 3.01 of the PHP license,      |
   | that is bundled with this package in the file LICENSE, and is        |
   | available through the world-wide-web at the following url:           |
   | http://www.php.net/license/3_01.txt                                  |
   | If you did not receive a copy of the PHP license and are unable to   |
   | obtain it through the world-wide-web, please send a note to          |
   | license@php.net so we can mail you a copy immediately.               |
   +----------------------------------------------------------------------+
*/

#ifndef incl_HPHP_BUILD_INFO_H_
#define incl_HPHP_BUILD_INFO_H_

#include <folly/Range.h>

namespace HPHP {

/*
 * Version identifier for the hhbc repo schema.  Normally this is determined at
 * build-time, but it can be overridden at run-time via the
 * HHVM_RUNTIME_REPO_SCHEMA environment variable.
 */
folly::StringPiece repoSchemaId();

/*
 * Unique identifier for an hhvm binary, determined at build-time.  Normally
 * this is a formatted version control hash, but it can fall back to system time
 * in some cases.
 */
folly::StringPiece compilerId();

/*
 * Replace %{schema} with the repo schema in path.
 */
std::string insertSchema(const char* path);

}

#endif
