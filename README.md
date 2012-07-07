aws
===

scripts and libraries for AWS http API

Most scripts make use of a wrapper class around Lincoln Stein's VM::EC2 and new AWS module.

They are written so that for commands which do not absolutely require AWS region and availability zone information one do not have to supply such information.

For example, 'describe_instance' command will describe all instances in all regions/az's and 'describe_instance' method will return VM::EC2 objects describeing all objects in all regions/az's.
