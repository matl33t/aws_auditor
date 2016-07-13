require "sport_ngin_aws_auditor"

module SportNginAwsAuditor
  describe RDSInstance do
    let(:tag_list) do
      [
        double('tag', key: 'cookie', value: 'chocolate'),
        double('tag', key: 'ice cream', value: 'oreo')
      ]
    end
    let(:tags) { double('tags', tag_list: tag_list) }
    let (:rds_instances) do
      [
        double('rds_instance',
          db_instance_identifier: "our-service",
          multi_az: false,
          db_instance_class: "db.m3.large",
          db_instance_status: "available",
          engine: "aurora",
          availability_zone: "us-east-1a",
          class: "Aws::RDS::Types::DBInstance"
        ),
        double('rds_instance',
          db_instance_identifier: "our-service",
          multi_az: false,
          db_instance_class: "db.t2.micro",
          db_instance_status: "available",
          engine: "mysql",
          availability_zone: "us-east-1a",
          class: "Aws::RDS::Types::DBInstance"
        ),
        double('rds_instance',
          db_instance_identifier: "our-service",
          multi_az: false,
          db_instance_class: "db.t2.small",
          db_instance_status: "available",
          engine: "mysql",
          availability_zone: "us-east-1a",
          class: "Aws::RDS::Types::DBInstance"
        )
      ]
    end
    let(:reserved_rds_instances) do
      [
        double('reserved_rds_instance',
          reserved_db_instances_offering_id: "555te4yy-1234-555c-5678-thisisafake!!",
          multi_az: false,
          db_instance_class: "db.t2.small",
          state: "active",
          product_description: "oracle-se2 (byol)",
          db_instance_count: 1,
          class: "Aws::RDS::Types::ReservedDBInstance"
        ),
        double('reserved_rds_instance',
          reserved_db_instances_offering_id: "555te4yy-1234-555c-5678-thisisafake!!",
          multi_az: false,
          db_instance_class: "db.m3.large",
          state: "active",
          product_description: "postgresql",
          db_instance_count: 2,
          class: "Aws::RDS::Types::ReservedDBInstance"
        )
      ]
    end
    let(:db_instances) { double('db_instances', db_instances: rds_instances) }
    let(:reserved_db_instances) { double('db_instances', reserved_db_instances: reserved_rds_instances) }
    let(:rds_client) do
      double('rds_client',
        describe_db_instances: db_instances,
        list_tags_for_resource: tags,
        describe_reserved_db_instances: reserved_db_instances
      )
    end
    let(:identity) { double('identity', account: 123456789) }
    let(:client) { double('client', get_caller_identity: identity) }

    before :each do
      allow(Aws::STS::Client).to receive(:new).and_return(client)
      allow(RDSInstance).to receive(:rds).and_return(rds_client)
    end

    after :each do
      RDSInstance.instance_variable_set("@instances", nil)
      RDSInstance.instance_variable_set("@reserved_instances", nil)
    end

    describe "#get_instances" do
      it "should make a rds_instance for each instance" do
        instances = RDSInstance.get_instances("tag_name")
        expect(instances.first).to be_an_instance_of(RDSInstance)
        expect(instances.last).to be_an_instance_of(RDSInstance)
      end

      it "should return an array of rds_instances sorted by engine and instance type" do
        instances = RDSInstance.get_instances("tag_name")
        expect(instances).to_not be_empty
        expect(instances.length).to eq(3)
        expect(instances.first.engine).to eq('Aurora')
        expect(instances.last.engine).to eq('MySQL')
        expect(instances.last.instance_type).to eq('db.t2.small')
      end

      it "should have proper variables set" do
        instances = RDSInstance.get_instances("tag_name")
        instance = instances.first
        expect(instance.id).to eq("our-service")
        expect(instance.multi_az).to eq("Single-AZ")
        expect(instance.instance_type).to eq("db.m3.large")
        expect(instance.engine).to eq("Aurora")
      end
    end

    describe "#get_reserved_instances" do
      it "should make a reserved_rds_instance for each instance" do
        reserved_instances = RDSInstance.get_reserved_instances
        expect(reserved_instances.first).to be_an_instance_of(RDSInstance)
        expect(reserved_instances.last).to be_an_instance_of(RDSInstance)
      end

      it "should return an array of reserved_rds_instances sorted by engine and instance type" do
        reserved_instances = RDSInstance.get_reserved_instances
        expect(reserved_instances).to_not be_empty
        expect(reserved_instances.length).to eq(2)
        expect(reserved_instances.first.engine).to eq('Oracle SE Two')
        expect(reserved_instances.last.instance_type).to eq('db.m3.large')
      end

      it "should have proper variables set" do
        reserved_instances = RDSInstance.get_reserved_instances
        reserved_instance = reserved_instances.first
        expect(reserved_instance.id).to eq("555te4yy-1234-555c-5678-thisisafake!!")
        expect(reserved_instance.multi_az).to eq("Single-AZ")
        expect(reserved_instance.instance_type).to eq("db.t2.small")
        expect(reserved_instance.engine).to eq("Oracle SE Two")
      end
    end

    describe "#to_s" do
      it "returns a string representation of a reserved rds instance" do
        reserved_instances = RDSInstance.get_reserved_instances
        expect(reserved_instances.first.to_s).to eq("Oracle SE Two Single-AZ db.t2.small")
      end

      it "returns a string representation of an on-demand rds instance" do
        instances = RDSInstance.get_instances("tag_name")
        expect(instances.first.to_s).to eq("Aurora Single-AZ db.m3.large")
      end
    end
  end
end
