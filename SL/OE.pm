#====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 1999-2003
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#  Contributors:
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Order entry module
# Quotation
#======================================================================

package OE;

use List::Util qw(max first);
use SL::AM;
use SL::Common;
use SL::CVar;
use SL::DBUtils;
use SL::IC;

sub transactions {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);

  my $query;
  my $ordnumber = 'ordnumber';
  my $quotation = '0';

  my @values;
  my $where;

  my $rate = ($form->{vc} eq 'customer') ? 'buy' : 'sell';

  if ($form->{type} =~ /_quotation$/) {
    $quotation = '1';
    $ordnumber = 'quonumber';
  }

  my $vc = $form->{vc} eq "customer" ? "customer" : "vendor";

  $query =
    qq|SELECT o.id, o.ordnumber, o.transdate, o.reqdate, | .
    qq|  o.amount, ct.name, o.netamount, o.${vc}_id, o.globalproject_id, | .
    qq|  o.closed, o.delivered, o.quonumber, o.shippingpoint, o.shipvia, | .
    qq|  o.transaction_description, | .
    qq|  o.marge_total, o.marge_percent, | .
    qq|  ex.$rate AS exchangerate, | .
    qq|  pr.projectnumber AS globalprojectnumber, | .
    qq|  e.name AS employee, s.name AS salesman | .
    qq|FROM oe o | .
    qq|JOIN $vc ct ON (o.${vc}_id = ct.id) | .
    qq|LEFT JOIN employee e ON (o.employee_id = e.id) | .
    qq|LEFT JOIN employee s ON (o.salesman_id = s.id) | .
    qq|LEFT JOIN exchangerate ex ON (ex.curr = o.curr | .
    qq|  AND ex.transdate = o.transdate) | .
    qq|LEFT JOIN project pr ON (o.globalproject_id = pr.id) | .
    qq|WHERE (o.quotation = ?) |;
  push(@values, $quotation);

  my ($null, $split_department_id) = split /--/, $form->{department};
  my $department_id = $form->{department_id} || $split_department_id;
  if ($department_id) {
    $query .= qq| AND o.department_id = ?|;
    push(@values, $department_id);
  }

  if ($form->{"project_id"}) {
    $query .=
      qq|AND ((globalproject_id = ?) OR EXISTS | .
      qq|  (SELECT * FROM orderitems oi | .
      qq|   WHERE oi.project_id = ? AND oi.trans_id = o.id))|;
    push(@values, $form->{"project_id"}, $form->{"project_id"});
  }

  if ($form->{"${vc}_id"}) {
    $query .= " AND o.${vc}_id = ?";
    push(@values, $form->{"${vc}_id"});

  } elsif ($form->{$vc}) {
    $query .= " AND ct.name ILIKE ?";
    push(@values, '%' . $form->{$vc} . '%');
  }

  if ($form->{employee_id}) {
    $query .= " AND o.employee_id = ?";
    push @values, conv_i($form->{employee_id});
  }

  if ($form->{salesman_id}) {
    $query .= " AND o.salesman_id = ?";
    push @values, conv_i($form->{salesman_id});
  }

  if (!$form->{open} && !$form->{closed}) {
    $query .= " AND o.id = 0";
  } elsif (!($form->{open} && $form->{closed})) {
    $query .= ($form->{open}) ? " AND o.closed = '0'" : " AND o.closed = '1'";
  }

  if (($form->{"notdelivered"} || $form->{"delivered"}) &&
      ($form->{"notdelivered"} ne $form->{"delivered"})) {
    $query .= $form->{"delivered"} ?
      " AND o.delivered " : " AND NOT o.delivered";
  }

  if ($form->{$ordnumber}) {
    $query .= qq| AND o.$ordnumber ILIKE ?|;
    push(@values, '%' . $form->{$ordnumber} . '%');
  }

  if($form->{transdatefrom}) {
    $query .= qq| AND o.transdate >= ?|;
    push(@values, conv_date($form->{transdatefrom}));
  }

  if($form->{transdateto}) {
    $query .= qq| AND o.transdate <= ?|;
    push(@values, conv_date($form->{transdateto}));
  }

  if($form->{reqdatefrom}) {
    $query .= qq| AND o.reqdate >= ?|;
    push(@values, conv_date($form->{reqdatefrom}));
  }

  if($form->{reqdateto}) {
    $query .= qq| AND o.reqdate <= ?|;
    push(@values, conv_date($form->{reqdateto}));
  }

  if ($form->{transaction_description}) {
    $query .= qq| AND o.transaction_description ILIKE ?|;
    push(@values, '%' . $form->{transaction_description} . '%');
  }

  my $sortdir   = !defined $form->{sortdir} ? 'ASC' : $form->{sortdir} ? 'ASC' : 'DESC';
  my $sortorder = join(', ', map { "${_} ${sortdir} " } ("o.id", $form->sort_columns("transdate", $ordnumber, "name")));
  my %allowed_sort_columns = (
    "transdate"               => "o.transdate",
    "reqdate"                 => "o.reqdate",
    "id"                      => "o.id",
    "ordnumber"               => "o.ordnumber",
    "quonumber"               => "o.quonumber",
    "name"                    => "ct.name",
    "employee"                => "e.name",
    "salesman"                => "e.name",
    "shipvia"                 => "o.shipvia",
    "transaction_description" => "o.transaction_description"
  );
  if ($form->{sort} && grep($form->{sort}, keys(%allowed_sort_columns))) {
    $sortorder = $allowed_sort_columns{$form->{sort}} . " ${sortdir}";
  }
  $query .= qq| ORDER by | . $sortorder;

  my $sth = $dbh->prepare($query);
  $sth->execute(@values) ||
    $form->dberror($query . " (" . join(", ", @values) . ")");

  my %id = ();
  $form->{OE} = [];
  while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {
    $ref->{exchangerate} = 1 unless $ref->{exchangerate};
    push @{ $form->{OE} }, $ref if $ref->{id} != $id{ $ref->{id} };
    $id{ $ref->{id} } = $ref->{id};
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub transactions_for_todo_list {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $query    = qq|SELECT id FROM employee WHERE login = ?|;
  my ($e_id)   = selectrow_query($form, $dbh, $query, $form->{login});

  $query       =
    qq|SELECT oe.id, oe.transdate, oe.reqdate, oe.quonumber, oe.transaction_description, oe.amount,
         CASE WHEN (COALESCE(oe.customer_id, 0) = 0) THEN 'vendor' ELSE 'customer' END AS vc,
         c.name AS customer,
         v.name AS vendor,
         e.name AS employee
       FROM oe
       LEFT JOIN customer c ON (oe.customer_id = c.id)
       LEFT JOIN vendor v   ON (oe.vendor_id   = v.id)
       LEFT JOIN employee e ON (oe.employee_id = e.id)
       WHERE (COALESCE(quotation, FALSE) = TRUE)
         AND (COALESCE(closed,    FALSE) = FALSE)
         AND ((oe.employee_id = ?) OR (oe.salesman_id = ?))
         AND NOT (oe.reqdate ISNULL)
         AND (oe.reqdate < current_date)
       ORDER BY transdate|;

  my $quotations = selectall_hashref_query($form, $dbh, $query, $e_id, $e_id);

  $main::lxdebug->leave_sub();

  return $quotations;
}

sub save {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database, turn off autocommit
  my $dbh = $form->dbconnect_noauto($myconfig);

  my ($query, @values, $sth, $null);
  my $exchangerate = 0;

  my $all_units = AM->retrieve_units($myconfig, $form);
  $form->{all_units} = $all_units;

  my $ic_cvar_configs = CVar->get_configs(module => 'IC',
                                          dbh    => $dbh);

  $form->{employee_id} = (split /--/, $form->{employee})[1] if !$form->{employee_id};
  unless ($form->{employee_id}) {
    $form->get_employee($dbh);
  }

  my $ml = ($form->{type} eq 'sales_order') ? 1 : -1;

  if ($form->{id}) {
    $query = qq|DELETE FROM custom_variables
                WHERE (config_id IN (SELECT id FROM custom_variable_configs WHERE module = 'IC'))
                  AND (sub_module = 'orderitems')
                  AND (trans_id IN (SELECT id FROM orderitems WHERE trans_id = ?))|;
    do_query($form, $dbh, $query, $form->{id});

    $query = qq|DELETE FROM orderitems WHERE trans_id = ?|;
    do_query($form, $dbh, $query, $form->{id});

    $query = qq|DELETE FROM shipto | .
             qq|WHERE trans_id = ? AND module = 'OE'|;
    do_query($form, $dbh, $query, $form->{id});

  } else {

    $query = qq|SELECT nextval('id')|;
    ($form->{id}) = selectrow_query($form, $dbh, $query);

    $query = qq|INSERT INTO oe (id, ordnumber, employee_id) VALUES (?, '', ?)|;
    do_query($form, $dbh, $query, $form->{id}, $form->{employee_id});
  }

  my $amount    = 0;
  my $linetotal = 0;
  my $discount  = 0;
  my $project_id;
  my $reqdate;
  my $taxrate;
  my $taxamount = 0;
  my $fxsellprice;
  my %taxbase;
  my @taxaccounts;
  my %taxaccounts;
  my $netamount = 0;

  $form->get_lists('price_factors' => 'ALL_PRICE_FACTORS');
  my %price_factors = map { $_->{id} => $_->{factor} } @{ $form->{ALL_PRICE_FACTORS} };
  my $price_factor;

  for my $i (1 .. $form->{rowcount}) {

    map({ $form->{"${_}_$i"} = $form->parse_amount($myconfig, $form->{"${_}_$i"}) } qw(qty ship));

    if ($form->{"id_$i"}) {

      # get item baseunit
      $query = qq|SELECT unit FROM parts WHERE id = ?|;
      my ($item_unit) = selectrow_query($form, $dbh, $query, $form->{"id_$i"});

      my $basefactor = 1;
      if (defined($all_units->{$item_unit}->{factor}) &&
          (($all_units->{$item_unit}->{factor} * 1) != 0)) {
        $basefactor = $all_units->{$form->{"unit_$i"}}->{factor} / $all_units->{$item_unit}->{factor};
      }
      my $baseqty = $form->{"qty_$i"} * $basefactor;

      $form->{"marge_percent_$i"} = $form->parse_amount($myconfig, $form->{"marge_percent_$i"}) * 1;
      $form->{"marge_total_$i"} = $form->parse_amount($myconfig, $form->{"marge_total_$i"}) * 1;
      $form->{"lastcost_$i"} = $form->{"lastcost_$i"} * 1;

      # set values to 0 if nothing entered
      $form->{"discount_$i"} = $form->parse_amount($myconfig, $form->{"discount_$i"}) / 100;

      $form->{"sellprice_$i"} = $form->parse_amount($myconfig, $form->{"sellprice_$i"});
      $fxsellprice = $form->{"sellprice_$i"};

      my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
      $dec = length($dec);
      my $decimalplaces = ($dec > 2) ? $dec : 2;

      $discount = $form->round_amount($form->{"sellprice_$i"} * $form->{"discount_$i"}, $decimalplaces);
      $form->{"sellprice_$i"} = $form->round_amount($form->{"sellprice_$i"} - $discount, $decimalplaces);

      $form->{"inventory_accno_$i"} *= 1;
      $form->{"expense_accno_$i"}   *= 1;

      $price_factor = $price_factors{ $form->{"price_factor_id_$i"} } || 1;
      $linetotal    = $form->round_amount($form->{"sellprice_$i"} * $form->{"qty_$i"} / $price_factor, 2);

      @taxaccounts = split(/ /, $form->{"taxaccounts_$i"});
      $taxrate     = 0;
      $taxdiff     = 0;

      map { $taxrate += $form->{"${_}_rate"} } @taxaccounts;

      if ($form->{taxincluded}) {
        $taxamount = $linetotal * $taxrate / (1 + $taxrate);
        $taxbase   = $linetotal - $taxamount;

        # we are not keeping a natural price, do not round
        $form->{"sellprice_$i"} =
          $form->{"sellprice_$i"} * (1 / (1 + $taxrate));
      } else {
        $taxamount = $linetotal * $taxrate;
        $taxbase   = $linetotal;
      }

      if ($form->round_amount($taxrate, 7) == 0) {
        if ($form->{taxincluded}) {
          foreach $item (@taxaccounts) {
            $taxamount = $form->round_amount($linetotal * $form->{"${item}_rate"} / (1 + abs($form->{"${item}_rate"})), 2);
            $taxaccounts{$item} += $taxamount;
            $taxdiff            += $taxamount;
            $taxbase{$item}     += $taxbase;
          }
          $taxaccounts{ $taxaccounts[0] } += $taxdiff;
        } else {
          foreach $item (@taxaccounts) {
            $taxaccounts{$item} += $linetotal * $form->{"${item}_rate"};
            $taxbase{$item}     += $taxbase;
          }
        }
      } else {
        foreach $item (@taxaccounts) {
          $taxaccounts{$item} += $taxamount * $form->{"${item}_rate"} / $taxrate;
          $taxbase{$item} += $taxbase;
        }
      }

      $netamount += $form->{"sellprice_$i"} * $form->{"qty_$i"} / $price_factor;

      $reqdate = ($form->{"reqdate_$i"}) ? $form->{"reqdate_$i"} : undef;

      # get pricegroup_id and save ist
      ($null, my $pricegroup_id) = split(/--/, $form->{"sellprice_pg_$i"});
      $pricegroup_id *= 1;

      # save detail record in orderitems table
      my $orderitems_id = $form->{"orderitems_id_$i"};
      ($orderitems_id)  = selectfirst_array_query($form, $dbh, qq|SELECT nextval('orderitemsid')|) if (!$orderitems_id);

      @values = ();
      $query = qq|INSERT INTO orderitems (
                    id, trans_id, parts_id, description, longdescription, qty, base_qty,
                    sellprice, discount, unit, reqdate, project_id, serialnumber, ship,
                    pricegroup_id, ordnumber, transdate, cusordnumber, subtotal,
                    marge_percent, marge_total, lastcost, price_factor_id, price_factor, marge_price_factor)
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                          (SELECT factor FROM price_factors WHERE id = ?), ?)|;
      push(@values,
           conv_i($orderitems_id), conv_i($form->{id}), conv_i($form->{"id_$i"}),
           $form->{"description_$i"}, $form->{"longdescription_$i"},
           $form->{"qty_$i"}, $baseqty,
           $fxsellprice, $form->{"discount_$i"},
           $form->{"unit_$i"}, conv_date($reqdate), conv_i($form->{"project_id_$i"}),
           $form->{"serialnumber_$i"}, $form->{"ship_$i"}, conv_i($pricegroup_id),
           $form->{"ordnumber_$i"}, conv_date($form->{"transdate_$i"}),
           $form->{"cusordnumber_$i"}, $form->{"subtotal_$i"} ? 't' : 'f',
           $form->{"marge_percent_$i"}, $form->{"marge_total_$i"},
           $form->{"lastcost_$i"},
           conv_i($form->{"price_factor_id_$i"}), conv_i($form->{"price_factor_id_$i"}),
           conv_i($form->{"marge_price_factor_$i"}));
      do_query($form, $dbh, $query, @values);

      $form->{"sellprice_$i"} = $fxsellprice;
      $form->{"discount_$i"} *= 100;

      CVar->save_custom_variables(module       => 'IC',
                                  sub_module   => 'orderitems',
                                  trans_id     => $orderitems_id,
                                  configs      => $ic_cvar_configs,
                                  variables    => $form,
                                  name_prefix  => 'ic_',
                                  name_postfix => "_$i",
                                  dbh          => $dbh);
    }
  }

  $reqdate = ($form->{reqdate}) ? $form->{reqdate} : undef;

  # add up the tax
  my $tax = 0;
  map { $tax += $form->round_amount($taxaccounts{$_}, 2) } keys %taxaccounts;

  $amount = $form->round_amount($netamount + $tax, 2);
  $netamount = $form->round_amount($netamount, 2);

  if ($form->{currency} eq $form->{defaultcurrency}) {
    $form->{exchangerate} = 1;
  } else {
    $exchangerate = $form->check_exchangerate($myconfig, $form->{currency}, $form->{transdate}, ($form->{vc} eq 'customer') ? 'buy' : 'sell');
  }

  $form->{exchangerate} = $exchangerate || $form->parse_amount($myconfig, $form->{exchangerate});

  my $quotation = $form->{type} =~ /_order$/ ? 'f' : 't';

  ($null, $form->{department_id}) = split(/--/, $form->{department}) if $form->{department};

  # save OE record
  $query =
    qq|UPDATE oe SET
         ordnumber = ?, quonumber = ?, cusordnumber = ?, transdate = ?, vendor_id = ?,
         customer_id = ?, amount = ?, netamount = ?, reqdate = ?, taxincluded = ?,
         shippingpoint = ?, shipvia = ?, notes = ?, intnotes = ?, curr = ?, closed = ?,
         delivered = ?, proforma = ?, quotation = ?, department_id = ?, language_id = ?,
         taxzone_id = ?, shipto_id = ?, payment_id = ?, delivery_vendor_id = ?, delivery_customer_id = ?,
         globalproject_id = ?, employee_id = ?, salesman_id = ?, cp_id = ?, transaction_description = ?, marge_total = ?, marge_percent = ?
       WHERE id = ?|;

  @values = ($form->{ordnumber} || '', $form->{quonumber},
             $form->{cusordnumber}, conv_date($form->{transdate}),
             conv_i($form->{vendor_id}), conv_i($form->{customer_id}),
             $amount, $netamount, conv_date($reqdate),
             $form->{taxincluded} ? 't' : 'f', $form->{shippingpoint},
             $form->{shipvia}, $form->{notes}, $form->{intnotes},
             substr($form->{currency}, 0, 3), $form->{closed} ? 't' : 'f',
             $form->{delivered} ? "t" : "f", $form->{proforma} ? 't' : 'f',
             $quotation, conv_i($form->{department_id}),
             conv_i($form->{language_id}), conv_i($form->{taxzone_id}),
             conv_i($form->{shipto_id}), conv_i($form->{payment_id}),
             conv_i($form->{delivery_vendor_id}),
             conv_i($form->{delivery_customer_id}),
             conv_i($form->{globalproject_id}), conv_i($form->{employee_id}),
             conv_i($form->{salesman_id}), conv_i($form->{cp_id}),
             $form->{transaction_description},
             $form->{marge_total} * 1, $form->{marge_percent} * 1,
             conv_i($form->{id}));
  do_query($form, $dbh, $query, @values);

  $form->{ordtotal} = $amount;

  # add shipto
  $form->{name} = $form->{ $form->{vc} };
  $form->{name} =~ s/--\Q$form->{"$form->{vc}_id"}\E//;

  if (!$form->{shipto_id}) {
    $form->add_shipto($dbh, $form->{id}, "OE");
  }

  # save printed, emailed, queued
  $form->save_status($dbh);

  # Link this record to the records it was created from.
  $form->{convert_from_oe_ids} =~ s/^\s+//;
  $form->{convert_from_oe_ids} =~ s/\s+$//;
  my @convert_from_oe_ids      =  split m/\s+/, $form->{convert_from_oe_ids};
  delete $form->{convert_from_oe_ids};

  if (scalar @convert_from_oe_ids) {
    RecordLinks->create_links('dbh'        => $dbh,
                              'mode'       => 'ids',
                              'from_table' => 'oe',
                              'from_ids'   => \@convert_from_oe_ids,
                              'to_table'   => 'oe',
                              'to_id'      => $form->{id},
      );

    $self->_close_quotations_rfqs('dbh'     => $dbh,
                                  'from_id' => \@convert_from_oe_ids,
                                  'to_id'   => $form->{id});
  }

  if (($form->{currency} ne $form->{defaultcurrency}) && !$exchangerate) {
    if ($form->{vc} eq 'customer') {
      $form->update_exchangerate($dbh, $form->{currency}, $form->{transdate}, $form->{exchangerate}, 0);
    }
    if ($form->{vc} eq 'vendor') {
      $form->update_exchangerate($dbh, $form->{currency}, $form->{transdate}, 0, $form->{exchangerate});
    }
  }

  $form->{saved_xyznumber} = $form->{$form->{type} =~ /_quotation$/ ?
                                       "quonumber" : "ordnumber"};

  Common::webdav_folder($form) if ($main::webdav);

  my $rc = $dbh->commit;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return $rc;
}

sub _close_quotations_rfqs {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(from_id to_id));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $query    = qq|SELECT quotation FROM oe WHERE id = ?|;
  my $sth      = prepare_query($form, $dbh, $query);

  do_statement($form, $sth, $query, conv_i($params{to_id}));

  my ($quotation) = $sth->fetchrow_array();

  if ($quotation) {
    $main::lxdebug->leave_sub();
    return;
  }

  my @close_ids;

  foreach my $from_id (@{ $params{from_id} }) {
    $from_id = conv_i($from_id);
    do_statement($form, $sth, $query, $from_id);
    ($quotation) = $sth->fetchrow_array();
    push @close_ids, $from_id if ($quotation);
  }

  $sth->finish();

  if (scalar @close_ids) {
    $query = qq|UPDATE oe SET closed = TRUE WHERE id IN (| . join(', ', ('?') x scalar @close_ids) . qq|)|;
    do_query($form, $dbh, $query, @close_ids);

    $dbh->commit() unless ($params{dbh});
  }

  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form, $spool) = @_;

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  # delete spool files
  my $query = qq|SELECT s.spoolfile FROM status s | .
              qq|WHERE s.trans_id = ?|;
  my @values = (conv_i($form->{id}));
  $sth = $dbh->prepare($query);
  $sth->execute(@values) || $self->dberror($query);

  my $spoolfile;
  my @spoolfiles = ();

  while (($spoolfile) = $sth->fetchrow_array) {
    push @spoolfiles, $spoolfile;
  }
  $sth->finish;

  # delete-values
  @values = (conv_i($form->{id}));

  # delete status entries
  $query = qq|DELETE FROM status | .
           qq|WHERE trans_id = ?|;
  do_query($form, $dbh, $query, @values);

  # delete OE record
  $query = qq|DELETE FROM oe | .
           qq|WHERE id = ?|;
  do_query($form, $dbh, $query, @values);

  # delete individual entries
  $query = qq|DELETE FROM orderitems | .
           qq|WHERE trans_id = ?|;
  do_query($form, $dbh, $query, @values);

  $query = qq|DELETE FROM shipto | .
           qq|WHERE trans_id = ? AND module = 'OE'|;
  do_query($form, $dbh, $query, @values);

  my $rc = $dbh->commit;
  $dbh->disconnect;

  if ($rc) {
    foreach $spoolfile (@spoolfiles) {
      unlink "$spool/$spoolfile" if $spoolfile;
    }
  }

  $main::lxdebug->leave_sub();

  return $rc;
}

sub retrieve {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect_noauto($myconfig);

  my ($query, $query_add, @values, @ids, $sth);

  my $ic_cvar_configs = CVar->get_configs(module => 'IC',
                                          dbh    => $dbh);

  # translate the ids (given by id_# and trans_id_#) into one array of ids, so we can join them later
  map {
    push @ids, $form->{"trans_id_$_"}
      if ($form->{"multi_id_$_"} and $form->{"trans_id_$_"})
  } (1 .. $form->{"rowcount"});

  if ($form->{rowcount} && scalar @ids) {
    $form->{convert_from_oe_ids} = join ' ', @ids;
  }

  # if called in multi id mode, and still only got one id, switch back to single id
  if ($form->{"rowcount"} and $#ids == 0) {
    $form->{"id"} = $ids[0];
    undef @ids;
  }

  my $query_add = '';
  if (!$form->{id}) {
    my $wday         = (localtime(time))[6];
    my $next_workday = $wday == 5 ? 3 : $wday == 6 ? 2 : 1;
    $query_add       = qq|, current_date AS transdate, date(current_date + interval '${next_workday} days') AS reqdate|;
  }

  # get default accounts
  $query = qq|SELECT (SELECT c.accno FROM chart c WHERE d.inventory_accno_id = c.id) AS inventory_accno,
                     (SELECT c.accno FROM chart c WHERE d.income_accno_id    = c.id) AS income_accno,
                     (SELECT c.accno FROM chart c WHERE d.expense_accno_id   = c.id) AS expense_accno,
                     (SELECT c.accno FROM chart c WHERE d.fxgain_accno_id    = c.id) AS fxgain_accno,
                     (SELECT c.accno FROM chart c WHERE d.fxloss_accno_id    = c.id) AS fxloss_accno,
              d.curr AS currencies
              $query_add
              FROM defaults d|;
  my $ref = selectfirst_hashref_query($form, $dbh, $query);
  map { $form->{$_} = $ref->{$_} } keys %$ref;

  ($form->{currency}) = split(/:/, $form->{currencies}) unless ($form->{currency});

  # set reqdate if this is an invoice->order conversion. If someone knows a better check to ensure
  # we come from invoices, feel free.
  $form->{reqdate} = $form->{deliverydate}
    if (    $form->{deliverydate}
        and $form->{callback} =~ /action=ar_transactions/);

  my $vc = $form->{vc} eq "customer" ? "customer" : "vendor";

  if ($form->{id} or @ids) {

    # retrieve order for single id
    # NOTE: this query is intended to fetch all information only ONCE.
    # so if any of these infos is important (or even different) for any item,
    # it will be killed out and then has to be fetched from the item scope query further down
    $query =
      qq|SELECT o.cp_id, o.ordnumber, o.transdate, o.reqdate,
           o.taxincluded, o.shippingpoint, o.shipvia, o.notes, o.intnotes,
           o.curr AS currency, e.name AS employee, o.employee_id, o.salesman_id,
           o.${vc}_id, cv.name AS ${vc}, o.amount AS invtotal,
           o.closed, o.reqdate, o.quonumber, o.department_id, o.cusordnumber,
           d.description AS department, o.payment_id, o.language_id, o.taxzone_id,
           o.delivery_customer_id, o.delivery_vendor_id, o.proforma, o.shipto_id,
           o.globalproject_id, o.delivered, o.transaction_description
         FROM oe o
         JOIN ${vc} cv ON (o.${vc}_id = cv.id)
         LEFT JOIN employee e ON (o.employee_id = e.id)
         LEFT JOIN department d ON (o.department_id = d.id) | .
        ($form->{id}
         ? "WHERE o.id = ?"
         : "WHERE o.id IN (" . join(', ', map("? ", @ids)) . ")"
        );
    @values = $form->{id} ? ($form->{id}) : @ids;
    $sth = prepare_execute_query($form, $dbh, $query, @values);

    $ref = $sth->fetchrow_hashref(NAME_lc);
    map { $form->{$_} = $ref->{$_} } keys %$ref;

    $form->{saved_xyznumber} = $form->{$form->{type} =~ /_quotation$/ ?
                                         "quonumber" : "ordnumber"};

    # set all entries for multiple ids blank that yield different information
    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      map { $form->{$_} = '' if ($ref->{$_} ne $form->{$_}) } keys %$ref;
    }

    # if not given, fill transdate with current_date
    $form->{transdate} = $form->current_date($myconfig)
      unless $form->{transdate};

    $sth->finish;

    if ($form->{delivery_customer_id}) {
      $query = qq|SELECT name FROM customer WHERE id = ?|;
      ($form->{delivery_customer_string}) = selectrow_query($form, $dbh, $query, $form->{delivery_customer_id});
    }

    if ($form->{delivery_vendor_id}) {
      $query = qq|SELECT name FROM customer WHERE id = ?|;
      ($form->{delivery_vendor_string}) = selectrow_query($form, $dbh, $query, $form->{delivery_vendor_id});
    }

    # shipto and pinted/mailed/queued status makes only sense for single id retrieve
    if (!@ids) {
      $query = qq|SELECT s.* FROM shipto s WHERE s.trans_id = ? AND s.module = 'OE'|;
      $sth = prepare_execute_query($form, $dbh, $query, $form->{id});

      $ref = $sth->fetchrow_hashref(NAME_lc);
      delete($ref->{id});
      map { $form->{$_} = $ref->{$_} } keys %$ref;
      $sth->finish;

      # get printed, emailed and queued
      $query = qq|SELECT s.printed, s.emailed, s.spoolfile, s.formname FROM status s WHERE s.trans_id = ?|;
      $sth = prepare_execute_query($form, $dbh, $query, $form->{id});

      while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
        $form->{printed} .= "$ref->{formname} " if $ref->{printed};
        $form->{emailed} .= "$ref->{formname} " if $ref->{emailed};
        $form->{queued}  .= "$ref->{formname} $ref->{spoolfile} " if $ref->{spoolfile};
      }
      $sth->finish;
      map { $form->{$_} =~ s/ +$//g } qw(printed emailed queued);
    }    # if !@ids

    my %oid = ('Pg'     => 'oid',
               'Oracle' => 'rowid');

    my $transdate = $form->{transdate} ? $dbh->quote($form->{transdate}) : "current_date";

    $form->{taxzone_id} = 0 unless ($form->{taxzone_id});

    # retrieve individual items
    # this query looks up all information about the items
    # stuff different from the whole will not be overwritten, but saved with a suffix.
    $query =
      qq|SELECT o.id AS orderitems_id,
           c1.accno AS inventory_accno, c1.new_chart_id AS inventory_new_chart, date($transdate) - c1.valid_from as inventory_valid,
           c2.accno AS income_accno,    c2.new_chart_id AS income_new_chart,    date($transdate) - c2.valid_from as income_valid,
           c3.accno AS expense_accno,   c3.new_chart_id AS expense_new_chart,   date($transdate) - c3.valid_from as expense_valid,
           oe.ordnumber AS ordnumber_oe, oe.transdate AS transdate_oe, oe.cusordnumber AS cusordnumber_oe,
           p.partnumber, p.assembly, o.description, o.qty,
           o.sellprice, o.parts_id AS id, o.unit, o.discount, p.bin, p.notes AS partnotes, p.inventory_accno_id AS part_inventory_accno_id,
           o.reqdate, o.project_id, o.serialnumber, o.ship, o.lastcost,
           o.ordnumber, o.transdate, o.cusordnumber, o.subtotal, o.longdescription,
           o.price_factor_id, o.price_factor, o.marge_price_factor,
           pr.projectnumber, p.formel,
           pg.partsgroup, o.pricegroup_id, (SELECT pricegroup FROM pricegroup WHERE id=o.pricegroup_id) as pricegroup
         FROM orderitems o
         JOIN parts p ON (o.parts_id = p.id)
         JOIN oe ON (o.trans_id = oe.id)
         LEFT JOIN chart c1 ON ((SELECT inventory_accno_id                   FROM buchungsgruppen WHERE id=p.buchungsgruppen_id) = c1.id)
         LEFT JOIN chart c2 ON ((SELECT income_accno_id_$form->{taxzone_id}  FROM buchungsgruppen WHERE id=p.buchungsgruppen_id) = c2.id)
         LEFT JOIN chart c3 ON ((SELECT expense_accno_id_$form->{taxzone_id} FROM buchungsgruppen WHERE id=p.buchungsgruppen_id) = c3.id)
         LEFT JOIN project pr ON (o.project_id = pr.id)
         LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id) | .
      ($form->{id}
       ? qq|WHERE o.trans_id = ?|
       : qq|WHERE o.trans_id IN (| . join(", ", map("?", @ids)) . qq|)|) .
      qq|ORDER BY o.$oid{$myconfig->{dbdriver}}|;

    @ids = $form->{id} ? ($form->{id}) : @ids;
    $sth = prepare_execute_query($form, $dbh, $query, @values);

    while ($ref = $sth->fetchrow_hashref(NAME_lc)) {
      # Retrieve custom variables.
      my $cvars = CVar->get_custom_variables(dbh        => $dbh,
                                             module     => 'IC',
                                             sub_module => 'orderitems',
                                             trans_id   => $ref->{orderitems_id},
                                            );
      map { $ref->{"ic_cvar_$_->{name}"} = $_->{value} } @{ $cvars };

      # Handle accounts.
      if (!$ref->{"part_inventory_accno_id"}) {
        map({ delete($ref->{$_}); } qw(inventory_accno inventory_new_chart inventory_valid));
      }
      delete($ref->{"part_inventory_accno_id"});

      # in collective order, copy global ordnumber, transdate, cusordnumber into item scope
      #   unless already present there
      # remove _oe entries afterwards
      map { $ref->{$_} = $ref->{"${_}_oe"} if ($ref->{$_} eq '') }
        qw|ordnumber transdate cusordnumber|
        if (@ids);
      map { delete $ref->{$_} } qw|ordnumber_oe transdate_oe cusordnumber_oe|;



      while ($ref->{inventory_new_chart} && ($ref->{inventory_valid} >= 0)) {
        my $query =
          qq|SELECT accno AS inventory_accno, | .
          qq|  new_chart_id AS inventory_new_chart, | .
          qq|  date($transdate) - valid_from AS inventory_valid | .
          qq|FROM chart WHERE id = $ref->{inventory_new_chart}|;
        ($ref->{inventory_accno}, $ref->{inventory_new_chart},
         $ref->{inventory_valid}) = selectrow_query($form, $dbh, $query);
      }

      while ($ref->{income_new_chart} && ($ref->{income_valid} >= 0)) {
        my $query =
          qq|SELECT accno AS income_accno, | .
          qq|  new_chart_id AS income_new_chart, | .
          qq|  date($transdate) - valid_from AS income_valid | .
          qq|FROM chart WHERE id = $ref->{income_new_chart}|;
        ($ref->{income_accno}, $ref->{income_new_chart},
         $ref->{income_valid}) = selectrow_query($form, $dbh, $query);
      }

      while ($ref->{expense_new_chart} && ($ref->{expense_valid} >= 0)) {
        my $query =
          qq|SELECT accno AS expense_accno, | .
          qq|  new_chart_id AS expense_new_chart, | .
          qq|  date($transdate) - valid_from AS expense_valid | .
          qq|FROM chart WHERE id = $ref->{expense_new_chart}|;
        ($ref->{expense_accno}, $ref->{expense_new_chart},
         $ref->{expense_valid}) = selectrow_query($form, $dbh, $query);
      }

      # delete orderitems_id in collective orders, so that they get cloned no matter what
      delete $ref->{orderitems_id} if (@ids);

      # get tax rates and description
      $accno_id = ($form->{vc} eq "customer") ? $ref->{income_accno} : $ref->{expense_accno};
      $query =
        qq|SELECT c.accno, t.taxdescription, t.rate, t.taxnumber | .
        qq|FROM tax t LEFT JOIN chart c on (c.id = t.chart_id) | .
        qq|WHERE t.id IN (SELECT tk.tax_id FROM taxkeys tk | .
        qq|               WHERE tk.chart_id = (SELECT id FROM chart WHERE accno = ?) | .
        qq|                 AND startdate <= $transdate ORDER BY startdate DESC LIMIT 1) | .
        qq|ORDER BY c.accno|;
      $stw = prepare_execute_query($form, $dbh, $query, $accno_id);
      $ref->{taxaccounts} = "";
      my $i = 0;
      while ($ptr = $stw->fetchrow_hashref(NAME_lc)) {
        if (($ptr->{accno} eq "") && ($ptr->{rate} == 0)) {
          $i++;
          $ptr->{accno} = $i;
        }
        $ref->{taxaccounts} .= "$ptr->{accno} ";
        if (!($form->{taxaccounts} =~ /\Q$ptr->{accno}\E/)) {
          $form->{"$ptr->{accno}_rate"}        = $ptr->{rate};
          $form->{"$ptr->{accno}_description"} = $ptr->{taxdescription};
          $form->{"$ptr->{accno}_taxnumber"}   = $ptr->{taxnumber};
          $form->{taxaccounts} .= "$ptr->{accno} ";
        }

      }

      chop $ref->{taxaccounts};

      push @{ $form->{form_details} }, $ref;
      $stw->finish;
    }
    $sth->finish;

  } else {

    # get last name used
    $form->lastname_used($dbh, $myconfig, $form->{vc})
      unless $form->{"$form->{vc}_id"};

  }

  $form->{exchangerate} = $form->get_exchangerate($dbh, $form->{currency}, $form->{transdate}, ($form->{vc} eq 'customer') ? "buy" : "sell");

  Common::webdav_folder($form) if ($main::webdav);

  my $rc = $dbh->commit;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return $rc;
}

sub order_details {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $form) = @_;

  # connect to database
  my $dbh = $form->dbconnect($myconfig);
  my $query;
  my @values = ();
  my $sth;
  my $nodiscount;
  my $yesdiscount;
  my $nodiscount_subtotal = 0;
  my $discount_subtotal = 0;
  my $item;
  my $i;
  my @partsgroup = ();
  my $partsgroup;
  my $position = 0;
  my $subtotal_header = 0;
  my $subposition = 0;

  my %oid = ('Pg'     => 'oid',
             'Oracle' => 'rowid');

  my (@project_ids, %projectnumbers);

  push(@project_ids, $form->{"globalproject_id"}) if ($form->{"globalproject_id"});

  $form->get_lists('price_factors' => 'ALL_PRICE_FACTORS',
                   'departments'   => 'ALL_DEPARTMENTS');
  my %price_factors;

  foreach my $pfac (@{ $form->{ALL_PRICE_FACTORS} }) {
    $price_factors{$pfac->{id}}  = $pfac;
    $pfac->{factor}             *= 1;
    $pfac->{formatted_factor}    = $form->format_amount($myconfig, $pfac->{factor});
  }

  # lookup department
  foreach my $dept (@{ $form->{ALL_DEPARTMENTS} }) {
    next unless $dept->{id} eq $form->{department_id};
    $form->{department} = $dept->{description};
    last;
  }

  # sort items by partsgroup
  for $i (1 .. $form->{rowcount}) {
    $partsgroup = "";
    if ($form->{"partsgroup_$i"} && $form->{groupitems}) {
      $partsgroup = $form->{"partsgroup_$i"};
    }
    push @partsgroup, [$i, $partsgroup];
    push(@project_ids, $form->{"project_id_$i"}) if ($form->{"project_id_$i"});
  }

  if (@project_ids) {
    $query = "SELECT id, projectnumber FROM project WHERE id IN (" .
      join(", ", map("?", @project_ids)) . ")";
    $sth = prepare_execute_query($form, $dbh, $query, @project_ids);
    while (my $ref = $sth->fetchrow_hashref()) {
      $projectnumbers{$ref->{id}} = $ref->{projectnumber};
    }
    $sth->finish();
  }

  $form->{"globalprojectnumber"} = $projectnumbers{$form->{"globalproject_id"}};

  $form->{discount} = [];

  $form->{TEMPLATE_ARRAYS} = { };
  IC->prepare_parts_for_printing();

  my $ic_cvar_configs = CVar->get_configs(module => 'IC');

  my @arrays =
    qw(runningnumber number description longdescription qty ship unit bin
       partnotes serialnumber reqdate sellprice listprice netprice
       discount p_discount discount_sub nodiscount_sub
       linetotal  nodiscount_linetotal tax_rate projectnumber
       price_factor price_factor_name partsgroup);

  push @arrays, map { "ic_cvar_$_->{name}" } @{ $ic_cvar_configs };

  my @tax_arrays = qw(taxbase tax taxdescription taxrate taxnumber);

  map { $form->{TEMPLATE_ARRAYS}->{$_} = [] } (@arrays, @tax_arrays);

  my $sameitem = "";
  foreach $item (sort { $a->[1] cmp $b->[1] } @partsgroup) {
    $i = $item->[0];

    if ($item->[1] ne $sameitem) {
      push(@{ $form->{TEMPLATE_ARRAYS}->{description} }, qq|$item->[1]|);
      $sameitem = $item->[1];

      map({ push(@{ $form->{TEMPLATE_ARRAYS}->{$_} }, "") } grep({ $_ ne "description" } @arrays));
    }

    $form->{"qty_$i"} = $form->parse_amount($myconfig, $form->{"qty_$i"});

    if ($form->{"id_$i"} != 0) {

      # add number, description and qty to $form->{number}, ....

      if ($form->{"subtotal_$i"} && !$subtotal_header) {
        $subtotal_header = $i;
        $position = int($position);
        $subposition = 0;
        $position++;
      } elsif ($subtotal_header) {
        $subposition += 1;
        $position = int($position);
        $position = $position.".".$subposition;
      } else {
        $position = int($position);
        $position++;
      }

      my $price_factor = $price_factors{$form->{"price_factor_id_$i"}} || { 'factor' => 1 };

      push @{ $form->{TEMPLATE_ARRAYS}->{runningnumber} },     $position;
      push @{ $form->{TEMPLATE_ARRAYS}->{number} },            $form->{"partnumber_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{description} },       $form->{"description_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{longdescription} },   $form->{"longdescription_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{qty} },               $form->format_amount($myconfig, $form->{"qty_$i"});
      push @{ $form->{TEMPLATE_ARRAYS}->{ship} },              $form->format_amount($myconfig, $form->{"ship_$i"});
      push @{ $form->{TEMPLATE_ARRAYS}->{unit} },              $form->{"unit_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{bin} },               $form->{"bin_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{partnotes} },         $form->{"partnotes_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{serialnumber} },      $form->{"serialnumber_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{reqdate} },           $form->{"reqdate_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{sellprice} },         $form->{"sellprice_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{listprice} },         $form->{"listprice_$i"};
      push @{ $form->{TEMPLATE_ARRAYS}->{price_factor} },      $price_factor->{formatted_factor};
      push @{ $form->{TEMPLATE_ARRAYS}->{price_factor_name} }, $price_factor->{description};
      push @{ $form->{TEMPLATE_ARRAYS}->{partsgroup} },        $form->{"partsgroup_$i"};

      my $sellprice     = $form->parse_amount($myconfig, $form->{"sellprice_$i"});
      my ($dec)         = ($sellprice =~ /\.(\d+)/);
      my $decimalplaces = max 2, length($dec);

      my $parsed_discount      = $form->parse_amount($myconfig, $form->{"discount_$i"});
      my $linetotal_exact      =                     $form->{"qty_$i"} * $sellprice * (100 - $parsed_discount) / 100 / $price_factor->{factor};
      my $linetotal            = $form->round_amount($linetotal_exact, 2);
      my $discount             = $form->round_amount($form->{"qty_$i"} * $sellprice * $parsed_discount / 100 / $price_factor->{factor} - ($linetotal - $linetotal_exact),
                                                     $decimalplaces);
      my $nodiscount_linetotal = $form->round_amount($form->{"qty_$i"} * $sellprice / $price_factor->{factor}, 2);
      $form->{"netprice_$i"}   = $form->round_amount($form->{"qty_$i"} ? ($linetotal / $form->{"qty_$i"}) : 0, 2);

      push @{ $form->{TEMPLATE_ARRAYS}->{netprice} }, ($form->{"netprice_$i"} != 0) ? $form->format_amount($myconfig, $form->{"netprice_$i"}, $decimalplaces) : '';

      $linetotal = ($linetotal != 0) ? $linetotal : '';

      push @{ $form->{TEMPLATE_ARRAYS}->{discount} },  ($discount  != 0) ? $form->format_amount($myconfig, $discount * -1, 2) : '';
      push @{ $form->{TEMPLATE_ARRAYS}->{p_discount} }, $form->{"discount_$i"};

      $form->{ordtotal}         += $linetotal;
      $form->{nodiscount_total} += $nodiscount_linetotal;
      $form->{discount_total}   += $discount;

      if ($subtotal_header) {
        $discount_subtotal   += $linetotal;
        $nodiscount_subtotal += $nodiscount_linetotal;
      }

      if ($form->{"subtotal_$i"} && $subtotal_header && ($subtotal_header != $i)) {
        push @{ $form->{TEMPLATE_ARRAYS}->{discount_sub} },   $form->format_amount($myconfig, $discount_subtotal,   2);
        push @{ $form->{TEMPLATE_ARRAYS}->{nodiscount_sub} }, $form->format_amount($myconfig, $nodiscount_subtotal, 2);

        $discount_subtotal   = 0;
        $nodiscount_subtotal = 0;
        $subtotal_header     = 0;

      } else {
        push @{ $form->{TEMPLATE_ARRAYS}->{discount_sub} },   "";
        push @{ $form->{TEMPLATE_ARRAYS}->{nodiscount_sub} }, "";
      }

      if (!$form->{"discount_$i"}) {
        $nodiscount += $linetotal;
      }

      push @{ $form->{TEMPLATE_ARRAYS}->{linetotal} }, $form->format_amount($myconfig, $linetotal, 2);
      push @{ $form->{TEMPLATE_ARRAYS}->{nodiscount_linetotal} }, $form->format_amount($myconfig, $nodiscount_linetotal, 2);

      push(@{ $form->{TEMPLATE_ARRAYS}->{projectnumber} }, $projectnumbers{$form->{"project_id_$i"}});

      my ($taxamount, $taxbase);
      my $taxrate = 0;

      map { $taxrate += $form->{"${_}_rate"} } split(/ /, $form->{"taxaccounts_$i"});

      if ($form->{taxincluded}) {

        # calculate tax
        $taxamount = $linetotal * $taxrate / (1 + $taxrate);
        $taxbase = $linetotal / (1 + $taxrate);
      } else {
        $taxamount = $linetotal * $taxrate;
        $taxbase   = $linetotal;
      }

      if ($taxamount != 0) {
        foreach my $accno (split / /, $form->{"taxaccounts_$i"}) {
          $taxaccounts{$accno} += $taxamount * $form->{"${accno}_rate"} / $taxrate;
          $taxbase{$accno}     += $taxbase;
        }
      }

      $tax_rate = $taxrate * 100;
      push(@{ $form->{TEMPLATE_ARRAYS}->{tax_rate} }, qq|$tax_rate|);

      if ($form->{"assembly_$i"}) {
        $sameitem = "";

        # get parts and push them onto the stack
        my $sortorder = "";
        if ($form->{groupitems}) {
          $sortorder = qq|ORDER BY pg.partsgroup, a.$oid{$myconfig->{dbdriver}}|;
        } else {
          $sortorder = qq|ORDER BY a.$oid{$myconfig->{dbdriver}}|;
        }

        $query = qq|SELECT p.partnumber, p.description, p.unit, a.qty, | .
	               qq|pg.partsgroup | .
	               qq|FROM assembly a | .
		             qq|  JOIN parts p ON (a.parts_id = p.id) | .
		             qq|    LEFT JOIN partsgroup pg ON (p.partsgroup_id = pg.id) | .
		             qq|    WHERE a.bom = '1' | .
		             qq|    AND a.id = ? | . $sortorder;
		    @values = ($form->{"id_$i"});
        $sth = $dbh->prepare($query);
        $sth->execute(@values) || $form->dberror($query);

        while (my $ref = $sth->fetchrow_hashref(NAME_lc)) {
          if ($form->{groupitems} && $ref->{partsgroup} ne $sameitem) {
            map({ push(@{ $form->{TEMPLATE_ARRAYS}->{$_} }, "") } grep({ $_ ne "description" } @arrays));
            $sameitem = ($ref->{partsgroup}) ? $ref->{partsgroup} : "--";
            push(@{ $form->{TEMPLATE_ARRAYS}->{description} }, $sameitem);
          }

          push(@{ $form->{TEMPLATE_ARRAYS}->{description} }, $form->format_amount($myconfig, $ref->{qty} * $form->{"qty_$i"}) . qq|, $ref->{partnumber}, $ref->{description}|);
          map({ push(@{ $form->{TEMPLATE_ARRAYS}->{$_} }, "") } grep({ $_ ne "description" } @arrays));
        }
        $sth->finish;
      }

      map { push @{ $form->{TEMPLATE_ARRAYS}->{"ic_cvar_$_->{name}"} }, $form->{"ic_cvar_$_->{name}_$i"} } @{ $ic_cvar_configs };
    }
  }

  my $tax = 0;
  foreach $item (sort keys %taxaccounts) {
    $tax += $taxamount = $form->round_amount($taxaccounts{$item}, 2);

    push(@{ $form->{TEMPLATE_ARRAYS}->{taxbase} },        $form->format_amount($myconfig, $taxbase{$item}, 2));
    push(@{ $form->{TEMPLATE_ARRAYS}->{tax} },            $form->format_amount($myconfig, $taxamount,      2));
    push(@{ $form->{TEMPLATE_ARRAYS}->{taxrate} },        $form->format_amount($myconfig, $form->{"${item}_rate"} * 100));
    push(@{ $form->{TEMPLATE_ARRAYS}->{taxdescription} }, $form->{"${item}_description"} . q{ } . 100 * $form->{"${item}_rate"} . q{%});
    push(@{ $form->{TEMPLATE_ARRAYS}->{taxnumber} },      $form->{"${item}_taxnumber"});
  }

  $form->{nodiscount_subtotal} = $form->format_amount($myconfig, $form->{nodiscount_total}, 2);
  $form->{discount_total}      = $form->format_amount($myconfig, $form->{discount_total}, 2);
  $form->{nodiscount}          = $form->format_amount($myconfig, $nodiscount, 2);
  $form->{yesdiscount}         = $form->format_amount($myconfig, $form->{nodiscount_total} - $nodiscount, 2);

  if($form->{taxincluded}) {
    $form->{subtotal} = $form->format_amount($myconfig, $form->{ordtotal} - $tax, 2);
  } else {
    $form->{subtotal} = $form->format_amount($myconfig, $form->{ordtotal}, 2);
  }

  $form->{ordtotal} = ($form->{taxincluded}) ? $form->{ordtotal} : $form->{ordtotal} + $tax;

  # format amounts
  $form->{quototal} = $form->{ordtotal} = $form->format_amount($myconfig, $form->{ordtotal}, 2);

  if ($form->{type} =~ /_quotation/) {
    $form->set_payment_options($myconfig, $form->{quodate});
  } else {
    $form->set_payment_options($myconfig, $form->{orddate});
  }

  $form->{username} = $myconfig->{name};

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub project_description {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $id) = @_;

  my $query = qq|SELECT description FROM project WHERE id = ?|;
  my ($value) = selectrow_query($form, $dbh, $query, $id);

  $main::lxdebug->leave_sub();

  return $value;
}

1;
