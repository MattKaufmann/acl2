#!/bin/bash

################################################################################

# Java Library -- ATJ -- Tests -- Compilation
#
# Copyright (C) 2018 Kestrel Institute (http://www.kestrel.edu)
#
# License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
#
# Author: Alessandro Coglio (coglio@kestrel.edu)

################################################################################

# This file compiles all the Java files generated by ATJ
# and all the handwritten test harness Java files.
# It assumes that OpenJDK Java 11 is in the path,
# but it may well work with other Java versions or implementations.

################################################################################

# stop on error:
set -e

# generate class files:
javac -cp ../aij/java/out/artifacts/AIJ_jar/AIJ.jar *.java
