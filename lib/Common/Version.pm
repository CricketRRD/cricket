$Common::global::gVersion = "Cricket version !!VERSION!! (!!RELDATE!!)";

$Common::global::gVersion =~ s/[!]!VERSION![!]/devel/;
1;
