Apache SolR superpowers for your ooor Ruby OpenERP proxies
==========================================================

Solarize is a [Sunspot](https://github.com/sunspot/sunspot) adapter for [Ooor](https://github.com/akretion/ooor).
That is you get full Sunspot [SolR](https://lucene.apache.org/solr/) search DSL for your OpenERP.

But it's much more than that!

The first killer feature is that it supports multiple OpenERP instances in just one Apache SolR collection (with SolRCloud, SolR can scale, right?).

The second killer feature is that it's made to load OpenERP Ooor proxies entirely form the SolR records without making a call into OpenERP! That is it transforms Solr in a lightning fast and unlimited scalability NoSQL data store for your OpenERP which used to belong to the relational world and consequently has scalability limitations. It can load flat fields and also associations that have been previously denormalized for SolR flat catalog.

That being said, once an Ooor proxy is loaded from SolR, it behaves just like a normal Ooor object and will make calls to its origin OpenERP if you ask it too (for instance if you call a method or if you load a relation that isn't stored in SolR...)

Solarize doesn't cover Sunspot indexation features. Instead it's built to work in association with the [solerp](https://github.com/akretion/solerp) OpenERP module which will index your OpenERP objects into SolR so you can retrieve them with solarize or any other SolR client.

example
=======


```ruby
Ooor.new(username:'admin', password: 'admin', url: 'http://localhost:8069', database: 'ooor_test', solr_url: 'http://localhost:8983/solr/test')

#flat fields

q=ProductProduct.solr_search do
  with(:name, "USB Adapter")
end
q.results

q=ProductProduct.solr_search do
  with(:id, "solr1 product.product 36")
end
q.results

q=ProductProduct.solr_search do
  with(:sale_ok, true)
end
q.results


#m2o

q=ProductProduct.solr_search do
  with(:categ_id, 7)
end
q.results

q=ProductProduct.solr_search do
  with('categ_id/name', "External Devices")
end
q.results

q=ProductProduct.solr_search do
  with('uom_id/name', "Dozen(s)")
end
q.results


#denormalized m2o
#supposing we included categ_id for denormalization into the product records in solerp

q=ProductProduct.solr_search do
  with('categ_id/parent_id/name', "All products / Saleable")
end
q.results


#o2m

q=ProductProduct.solr_search do
  with(:seller_ids, 46)
end
q.results

q=ProductProduct.solr_search do
  with('seller_ids/name/name', 'Mediapole')
end
q.results


#m2m

q=ProductProduct.solr_search do
  with(:message_ids, 81)
end
q.results

q=ProductProduct.solr_search do
  with('message_ids/record_name', '[SW24] Switch, 24 ports')
end
q.results
```

Read Sunspot documentation for more details
